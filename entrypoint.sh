#!/usr/bin/env sh
set -e

SERVER_IP="${SERVER_IP:-}"
API_URL="${API_URL:-https://raw.githubusercontent.com/roydvs/docker-vpn-gate/main/servers.csv}"
SOCKS_PORT="${SOCKS_PORT:-1080}"
HTTP_PORT="${HTTP_PORT:-8080}"
OVPN_CONFIG="${OVPN_CONFIG:-/vpn/config.ovpn}"
TMP_OVPN="/tmp/config.ovpn"

PIDS=""

start_daemon() {
    "$@" &
    local pid=$!
    PIDS="$PIDS $pid"
    echo "Started $1 with PID $pid"
}

cleanup() {
    echo "Signal received, cleaning up PIDS: $PIDS"

    for pid in $PIDS; do
        kill "$pid" 2>/dev/null || true
    done

    pkill -9 openvpn || true
    exit 0
}

cleanup_vpn() {
    echo "Cleaning up old VPN processes..."
    pkill -9 openvpn || true
    ip link delete tun0 >/dev/null 2>&1 || true
    sleep 2
}

prepare_vpn_config() {
    if [ -f "$OVPN_CONFIG" ]; then
        echo "Using mounted config: $OVPN_CONFIG"
        cat "$OVPN_CONFIG" > "$TMP_OVPN"
    else
        echo "Fetching fresh nodes from VPN Gate API..."
        echo "API: $API_URL"

        local raw_data=$(curl -sL --connect-timeout 15 "$API_URL" | tr -d '\r' | grep -vE '^#|^\*|^$')
        
        if [ -z "$raw_data" ]; then
            echo "Error: Failed to fetch data from VPN Gate API." >&2
            return 1
        fi

        local selected_node=$(echo "$raw_data" | \
            sort -t',' -k3 -nr | head -n 20 | shuf -n 1)

        if [ -n "$SERVER_IP" ]; then
            echo "Try to find the server config: $SERVER_IP"
            local tmp_selected_node=$(echo "$raw_data" | grep "$SERVER_IP")
            if [ -n "$tmp_selected_node" ]; then
                selected_node="$tmp_selected_node"
            else
                echo "Not found the server config: $SERVER_IP"
            fi
        fi

        local server_ip=$(echo "$selected_node" | cut -d',' -f2)
        local country=$(echo "$selected_node" | cut -d',' -f6)
        local score=$(echo "$selected_node" | cut -d',' -f3)
        local b64_config=$(echo "$selected_node" | cut -d',' -f15)

        if [ "${b64_config#"IyMj"}" == "$b64_config" ]; then
            echo "Error: Failed to parse data from VPN Gate response." >&2
            echo "Error: Selected node: $selected_node" >&2
            return 1
        fi

        echo "------------------------------------------------"
        echo "Selected VPN Node: $server_ip ($country , $score)"
        echo "------------------------------------------------"

        echo "$b64_config" | base64 -d > "$TMP_OVPN"
    fi

    printf "\n<auth-user-pass>\nvpn\nvpn\n</auth-user-pass>\n" >> "$TMP_OVPN"
    printf "\ndata-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-128-CBC\n" >> "$TMP_OVPN"
    printf "\ndata-ciphers-fallback AES-128-CBC\n" >> "$TMP_OVPN"
    printf "\nverify-x509-name opengw.net name\n" >> "$TMP_OVPN"
    printf "\nremote-cert-tls server\n" >> "$TMP_OVPN"
    printf "\nauth-nocache\n" >> "$TMP_OVPN"

    return 0
}

mkdir -p /dev/net
[ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200

trap cleanup INT TERM

start_daemon microsocks -p "$SOCKS_PORT" -i 0.0.0.0
HTTP_PROXY_CONFIG="/tmp/tinyproxy.conf"
printf "Port $HTTP_PORT\nListen 0.0.0.0\nAllow 0.0.0.0/0\nLogFile \"/dev/stdout\"\nLogLevel Error\n" > "$HTTP_PROXY_CONFIG"
start_daemon tinyproxy -c "$HTTP_PROXY_CONFIG"
echo "Proxies started: SOCKS5=$SOCKS_PORT, HTTP=$HTTP_PORT"

CONFIG_MAX_RETRIES=5
CONFIG_RETRY_COUNT=0
CONN_MAX_RETRIES=5
CONN_RETRY_COUNT=0
while true; do
    cleanup_vpn

    if ! prepare_vpn_config; then
        CONFIG_RETRY_COUNT=$((CONFIG_RETRY_COUNT + 1))

        if [ "$CONFIG_RETRY_COUNT" -gt "$CONFIG_MAX_RETRIES" ]; then
            echo "------------------------------------------------"
            echo "ERROR: Failed to fetch config after $CONFIG_MAX_RETRIES attempts."
            echo "------------------------------------------------"
            exit 1
        fi

        echo "Retry $CONFIG_RETRY_COUNT/$CONFIG_MAX_RETRIES: Cannot prepare vpn config, retrying in 5s..."
        sleep 5
        continue
    else
        CONFIG_RETRY_COUNT=0
    fi

    echo "Starting OpenVPN..."
    openvpn --config "$TMP_OVPN" --dev tun0 &

    CONNECTED=false
    for i in $(seq 1 30); do
        if ip link show tun0 > /dev/null 2>&1; then
            if ip addr show tun0 | grep -q "inet "; then
                CONNECTED=true
                break
            fi
        fi
        sleep 1
    done

    if [ "$CONNECTED" = false ]; then
        CONN_RETRY_COUNT=$((CONN_RETRY_COUNT + 1))

        if [ "$CONN_RETRY_COUNT" -gt "$CONN_MAX_RETRIES" ]; then
            echo "------------------------------------------------"
            echo "ERROR: Failed to connect VPN server after $CONN_MAX_RETRIES attempts."
            echo "------------------------------------------------"
            exit 1
        fi

        echo "Retry $CONN_RETRY_COUNT/$CONN_MAX_RETRIES: VPN Connection failed/timeout. Trying next node..."
        continue
    else
        CONN_RETRY_COUNT=0
    fi

    echo "VPN Connected. Setting DNS..."
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf

    echo "Entering health check..."
    FAIL_MAX=3
    FAIL_COUNT=0
    PING_DURATION=20
    while true; do
        if ! ping -c 1 -W 10 1.1.1.1 -I tun0 > /dev/null 2>&1; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo "Ping failed ($FAIL_COUNT/$FAIL_MAX)..."
        else
            if [ "$FAIL_COUNT" -gt 0 ]; then
                echo "Ping OK"
            fi
            FAIL_COUNT=0
        fi

        if [ "$FAIL_COUNT" -gt "$FAIL_MAX" ] || ! pgrep openvpn > /dev/null; then
            echo "VPN Link is dead. Reconnecting..."
            break
        fi
        sleep "$PING_DURATION" & 
        SLEEP_PID=$!
        wait $SLEEP_PID
    done
done