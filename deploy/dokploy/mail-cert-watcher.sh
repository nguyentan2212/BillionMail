#!/bin/sh
set -u

reload_file="${MAIL_CERT_RELOAD_FILE:-/etc/ssl/mail/.reload}"
interval="${MAIL_CERT_RELOAD_INTERVAL:-30}"

if [ "$#" -eq 0 ]; then
  echo "mail-cert-watcher requires a reload command" >&2
  exit 2
fi

seen="$(cat "$reload_file" 2>/dev/null || true)"

while sleep "$interval"; do
  current="$(cat "$reload_file" 2>/dev/null || true)"

  if [ -z "$current" ] || [ "$current" = "$seen" ]; then
    continue
  fi

  if "$@"; then
    seen="$current"
    echo "Reloaded mail service after certificate update"
  else
    echo "Mail service reload failed; retrying in ${interval}s" >&2
  fi
done
