# Docker VPN Gate

[![Build Status](https://img.shields.io/github/actions/workflow/status/roydvs/docker-vpn-gate/docker-publish.yaml?logo=github)](https://github.com/roydvs/docker-vpn-gate/actions/workflows/docker-publish.yaml)
[![GHCR](https://img.shields.io/badge/ghcr.io-roydvs%2Fdocker--vpn--gate-blue?logo=github)](https://github.com/roydvs/docker-vpn-gate/pkgs/container/docker-vpn-gate)
[![License](https://img.shields.io/github/license/roydvs/docker-vpn-gate)](LICENSE)
[![Last Sync](https://img.shields.io/github/last-commit/roydvs/docker-vpn-gate?path=servers.csv&label=last%20sync)](servers.csv)


A lightweight Alpine-based container that automatically connects to [VPN Gate](https://www.vpngate.net/) and exposes the connection via SOCKS5 and HTTP proxies.

## Features
- **Auto-Selection**: Automatically fetches and connects to the best-performing VPN Gate nodes.
- **Dual Proxy Support**: 
  - **SOCKS5**: Powered by [Microsocks](https://github.com/rofl0r/microsocks) (Port 1080)
  - **HTTP/HTTPS**: Powered by [Tinyproxy](https://github.com/tinyproxy/tinyproxy) (Port 8080)
- **Flexible**: Use auto-selected nodes, specific IPs, or your own `.ovpn` files.
- **Minimalist**: Tiny footprint using a multi-stage Alpine Linux build.

## Quick Start

### 1. Run the Container
```bash
docker run -d \
  --name vpn-gate \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -p 1080:1080 -p 8080:8080 \
  ghcr.io/roydvs/docker-vpn-gate
```

### 2. Verify Connection
**Check via SOCKS5:**
```bash
curl -x socks5://localhost:1080 https://www.cloudflare.com/cdn-cgi/trace
```
**Check via HTTP:**
```bash
curl -x http://localhost:8080 https://www.cloudflare.com/cdn-cgi/trace
```

## Configuration

### Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_IP` | (empty) | Connect to a specific VPN IP. If empty, the highest-score server is chosen. |
| `SOCKS_PORT`| `1080` | Internal port for Microsocks. |
| `HTTP_PORT` | `8080` | Internal port for Tinyproxy. |
| `API_URL`   | `https://raw.githubusercontent.com/roydvs/docker-vpn-gate/main/servers.csv` | VPN Gate server list API. |

### Reliability & Mirroring

To ensure high availability in restricted network environments, this project includes a built-in GitHub Action that mirrors the VPN Gate server list.

- **Default API Mirror**: `https://raw.githubusercontent.com/roydvs/docker-vpn-gate/main/servers.csv`
- **Official API**: `https://www.vpngate.net/api/iphone/` (Use this by setting the `API_URL` environment variable if needed).

### Advanced Usage

**Custom OpenVPN Config:**
Mount your own `.ovpn` file to bypass the auto-selection API.
```bash
docker run -d --cap-add=NET_ADMIN --device /dev/net/tun \
  -v /path/to/my.ovpn:/vpn/config.ovpn \
  ghcr.io/roydvs/docker-vpn-gate
```

**Docker Compose:**
```yaml
services:
  vpn-gate:
    image: ghcr.io/roydvs/docker-vpn-gate
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    ports:
      - "1080:1080"
      - "8080:8080"
    environment:
      - SERVER_IP=
      - SOCKS_PORT=1080
      - HTTP_PORT=8080
    restart: unless-stopped
```

## Security & Privacy

- **Privileges**: Requires `--cap-add=NET_ADMIN` to configure the TUN interface.
- **VPN Nodes**: Servers are provided by volunteers via VPN Gate. Use at your own risk; traffic is visible to the node operator.
- **Credentials**: Uses the standard `vpn:vpn` credentials for VPN Gate authentication.

## Credits & License

- **Project License**: [MIT](LICENSE)
- **Component Licenses**:
  - [OpenVPN](https://openvpn.net/): GNU GPLv2
  - [Tinyproxy](https://github.com/tinyproxy/tinyproxy): GNU GPLv2
  - [Microsocks](https://github.com/rofl0r/microsocks): MIT
  - [VPN Gate](https://www.vpngate.net/): Academic Project by University of Tsukuba

**Disclaimer**: This tool is for educational and testing purposes. Users are responsible for complying with local regulations regarding VPN usage and internet privacy.