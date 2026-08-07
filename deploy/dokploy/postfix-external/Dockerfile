FROM billionmail/postfix:1.6
COPY deploy/dokploy/postfix-external/postfix.sh /postfix.sh
COPY deploy/dokploy/mail-cert-watcher.sh /usr/local/bin/mail-cert-watcher
RUN chmod 0755 /postfix.sh /usr/local/bin/mail-cert-watcher
