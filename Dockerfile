FROM alpine:latest AS builder

RUN apk add --no-cache build-base git

RUN git clone https://github.com/rofl0r/microsocks.git /tmp/microsocks && \
    cd /tmp/microsocks && \
    make

FROM alpine:latest

RUN apk add --no-cache openvpn curl ca-certificates iproute2 tinyproxy iptables

COPY --from=builder /tmp/microsocks/microsocks /usr/local/bin/microsocks

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 1080 8080

ENTRYPOINT ["/entrypoint.sh"]
