FROM redis:7.4.2-alpine

RUN apk add --no-cache \
    ca-certificates \
    haproxy

COPY deploy/dokploy/redis-gateway/entrypoint.sh /usr/local/bin/redis-gateway-entrypoint
RUN chmod +x /usr/local/bin/redis-gateway-entrypoint

ENTRYPOINT ["/usr/local/bin/redis-gateway-entrypoint"]
