#!/usr/bin/env bash
# gb10-syslog.sh - make the GB10 (ai-01) a syslog receiver for Horizon Connection Server events.
#
# Receives on UDP+TCP 5514 (same port as the existing ELK target) with rsyslog, which is already
# installed and running on DGX OS, and writes one file per sender per day:
#     /srv/ai/logs/syslog/<sender>/YYYY-MM-DD.log     (group aiops, readable by the analyzer)
# Remote messages are kept OUT of /var/log/syslog. Files older than RETENTION_DAYS are removed daily.
#
# Usage:
#   sudo bash gb10-syslog.sh --check    # show what would be done, change nothing
#   sudo bash gb10-syslog.sh            # configure and restart rsyslog
#   sudo bash gb10-syslog.sh --test     # send a test message to ourselves and show where it landed
set -euo pipefail

# ============================== PARAMETERS ===================================
PORT=5514
LOG_ROOT="/srv/ai/logs/syslog"
AI_GROUP="aiops"
RETENTION_DAYS=90
ALLOWED_SENDERS=""            # optional, e.g. "10.0.0.0/24" - empty = accept from anyone that can reach the port
# =============================================================================

MODE="${1:-run}"
if [ "$(id -u)" -ne 0 ]; then exec sudo bash "$0" "$@"; fi

CONF=/etc/rsyslog.d/30-ai-remote.conf
CRON=/etc/cron.daily/ai-syslog-retention
AA_LOCAL=/etc/apparmor.d/local/usr.sbin.rsyslogd
ok()   { printf '  [OK]   %s\n' "$*"; }
chg()  { printf '  [SET]  %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
die()  { printf '  [FAIL] %s\n' "$*"; exit 1; }

if [ "$MODE" = "--test" ]; then
  echo "== Test"
  MSG="gb10-syslog test $(date +%s)"
  logger -n 127.0.0.1 -P "$PORT" -d -t gb10-test "$MSG"      # UDP
  logger -n 127.0.0.1 -P "$PORT" -T -t gb10-test "$MSG (tcp)" # TCP
  sleep 2
  if grep -rl "$MSG" "$LOG_ROOT" 2>/dev/null; then ok "test message received (UDP and/or TCP) - file listed above"
  else die "test message not found under $LOG_ROOT - check 'journalctl -u rsyslog -n 50'"; fi
  grep -q "$MSG" /var/log/syslog 2>/dev/null && warn "test message also landed in /var/log/syslog" || ok "not duplicated into /var/log/syslog"
  exit 0
fi

echo "== Syslog receiver: port $PORT/udp+tcp -> $LOG_ROOT (mode: $MODE)"

# --- 1. Pre-checks ----------------------------------------------------------
echo "1) Pre-checks"
systemctl is-active --quiet rsyslog && ok "rsyslog running ($(rsyslogd -v | head -1 | awk '{print $2}'))" || die "rsyslog is not running"
getent group "$AI_GROUP" >/dev/null || die "group $AI_GROUP missing - run gb10-prepare.sh first"
[ -d "$(dirname "$LOG_ROOT")" ] || die "$(dirname "$LOG_ROOT") missing - run gb10-prepare.sh first"
if ss -lntu | awk '{print $5}' | grep -qE "[:.]$PORT\$"; then
  if ss -lntup 2>/dev/null | grep -E "[:.]$PORT\b" | grep -q rsyslogd; then ok "port $PORT already served by rsyslog"
  else die "port $PORT is in use by another process: $(ss -lntup | grep -E "[:.]$PORT\b" | head -1)"; fi
else ok "port $PORT is free"; fi
# imudp/imtcp may not be loaded twice - only load them if the main config does not
LOAD_UDP=1; LOAD_TCP=1
grep -hEq '^\s*(module\(load="imudp"|\$ModLoad imudp)' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null \
  && ! grep -q 'imudp' "$CONF" 2>/dev/null && { LOAD_UDP=0; ok "imudp already loaded elsewhere"; }
grep -hEq '^\s*(module\(load="imtcp"|\$ModLoad imtcp)' /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null \
  && ! grep -q 'imtcp' "$CONF" 2>/dev/null && { LOAD_TCP=0; ok "imtcp already loaded elsewhere"; }
PRIV_USER="$(grep -hE '^\s*\$PrivDropToUser' /etc/rsyslog.conf 2>/dev/null | awk '{print $2}' | tail -1 || true)"
ok "rsyslog drops privileges to: ${PRIV_USER:-root (no PrivDropToUser)}"
AA_STATE="not loaded"
if command -v aa-status >/dev/null && aa-status 2>/dev/null | grep -q rsyslogd; then
  aa-status 2>/dev/null | sed -n '/enforce mode/,/complain mode/p' | grep -q rsyslogd && AA_STATE="enforce" || AA_STATE="complain"
fi
ok "AppArmor profile for rsyslogd: $AA_STATE"

CONTENT="# Managed by gb10-syslog.sh - remote syslog (Horizon events) for log analysis
$( [ $LOAD_UDP -eq 1 ] && echo 'module(load="imudp")' || true )
$( [ $LOAD_TCP -eq 1 ] && echo 'module(load="imtcp")' || true )
$( [ -n "$ALLOWED_SENDERS" ] && printf '$AllowedSender UDP, %s\n$AllowedSender TCP, %s\n' "$ALLOWED_SENDERS" "$ALLOWED_SENDERS" || true )
template(name=\"AiRemoteFile\" type=\"string\" string=\"$LOG_ROOT/%fromhost%/%\$year%-%\$month%-%\$day%.log\")
template(name=\"AiRemoteLine\" type=\"string\" string=\"%timegenerated:::date-rfc3339% %fromhost% %syslogtag%%msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\\n\")

ruleset(name=\"ai_remote\") {
  action(type=\"omfile\" dynaFile=\"AiRemoteFile\" template=\"AiRemoteLine\"
         createDirs=\"on\" dirCreateMode=\"02775\" fileCreateMode=\"0664\"
         dirGroup=\"$AI_GROUP\" fileGroup=\"$AI_GROUP\")
  stop
}

input(type=\"imudp\" port=\"$PORT\" ruleset=\"ai_remote\")
input(type=\"imtcp\" port=\"$PORT\" ruleset=\"ai_remote\")"

if [ "$MODE" = "--check" ]; then
  echo; echo "Would write $CONF:"; echo "$CONTENT" | sed 's/^/    /'
  echo; echo "Check finished - nothing changed."; exit 0
fi

# --- 2. Log folder ----------------------------------------------------------
echo; echo "2) Log folder"
mkdir -p "$LOG_ROOT"
chown "${PRIV_USER:-root}:$AI_GROUP" "$LOG_ROOT"; chmod 2775 "$LOG_ROOT"
ok "$LOG_ROOT owned by ${PRIV_USER:-root}:$AI_GROUP, 2775"

# --- 3. AppArmor (only if the rsyslogd profile is enforced) ------------------
echo; echo "3) AppArmor"
if [ "$AA_STATE" = "enforce" ]; then
  RULE="  $LOG_ROOT/ r,
  $LOG_ROOT/** rw,"
  if [ -f "$AA_LOCAL" ] && grep -qF "$LOG_ROOT/** rw," "$AA_LOCAL"; then ok "$AA_LOCAL already allows $LOG_ROOT"
  else printf '%s\n' "# gb10-syslog.sh" "$RULE" >> "$AA_LOCAL"; chg "$AA_LOCAL: allow $LOG_ROOT"
       apparmor_parser -r /etc/apparmor.d/usr.sbin.rsyslogd && ok "profile reloaded"; fi
else ok "no enforced profile - nothing to do"; fi

# --- 4. rsyslog config ------------------------------------------------------
echo; echo "4) rsyslog"
if [ -f "$CONF" ] && [ "$(cat "$CONF")" = "$CONTENT" ]; then ok "$CONF up to date"
else [ -f "$CONF" ] && cp -p "$CONF" "$CONF.bak-$(date +%Y%m%d-%H%M%S)"; printf '%s\n' "$CONTENT" > "$CONF"; chg "$CONF"; fi
rsyslogd -N1 -f /etc/rsyslog.conf >/tmp/rsyslog-check.txt 2>&1 || { cat /tmp/rsyslog-check.txt; die "rsyslog config check failed - not restarting"; }
ok "rsyslogd -N1 config check passed"
systemctl restart rsyslog; sleep 1
systemctl is-active --quiet rsyslog && ok "rsyslog restarted" || die "rsyslog failed to start - see journalctl -u rsyslog"
ss -lntu | grep -E "[:.]$PORT\b" | awk '{print "  [OK]   listening: "$1" "$5}' || warn "nothing listening on $PORT after restart - check journalctl -u rsyslog"

# --- 5. Retention -----------------------------------------------------------
echo; echo "5) Retention"
cat > "$CRON" <<EOF
#!/bin/sh
# Managed by gb10-syslog.sh - delete remote syslog files older than $RETENTION_DAYS days
find "$LOG_ROOT" -type f -name '*.log' -mtime +$RETENTION_DAYS -delete
find "$LOG_ROOT" -mindepth 1 -type d -empty -delete
EOF
chmod 755 "$CRON"; ok "$CRON ($RETENTION_DAYS days)"

echo
echo "== Done. Next:"
echo "   sudo bash $0 --test"
echo "   Horizon Console > Settings > Event Configuration > Syslog > Add:  ai-01.<domain>:$PORT"
echo "   Then watch:  ls -l $LOG_ROOT/   and   tail -f $LOG_ROOT/<cs-host>/\$(date +%F).log"
