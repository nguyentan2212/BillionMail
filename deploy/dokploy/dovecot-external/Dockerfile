FROM billionmail/dovecot:1.6
COPY deploy/dokploy/dovecot-external/dovecot.sh /dovecot.sh
COPY deploy/dokploy/mail-cert-watcher.sh /usr/local/bin/mail-cert-watcher
RUN chmod 0755 /dovecot.sh /usr/local/bin/mail-cert-watcher
