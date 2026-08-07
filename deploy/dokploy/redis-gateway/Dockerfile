FROM alpine:3.20

RUN apk add --no-cache \
    ca-certificates \
    haproxy \
    redis

COPY deploy/dokploy/redis-gateway/entrypoint.sh /usr/local/bin/redis-gateway-entrypoint
RUN chmod +x /usr/local/bin/redis-gateway-entrypoint

ENTRYPOINT ["/usr/local/bin/redis-gateway-entrypoint"]
