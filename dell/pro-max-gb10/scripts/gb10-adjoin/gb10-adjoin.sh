#!/usr/bin/env bash
# gb10-adjoin.sh - join a Dell Pro Max GB10 (DGX OS / Ubuntu 24.04) to Active Directory
# with realmd + SSSD, restrict logins to AD groups and grant sudo to an AD group.
#
# Usage:
#   1. Fill in the PARAMETERS section below.
#   2. sudo bash gb10-adjoin.sh --check    # pre-checks only, changes nothing
#   3. sudo bash gb10-adjoin.sh            # full run (prompts for the join password)
#
# Safe to re-run: skips the join if already joined and re-applies the configuration.
# Keep a local admin session open while testing AD logins.
set -euo pipefail

# ============================== PARAMETERS ===================================
DOMAIN="ad.example.local"                                  # AD DNS domain
JOIN_USER="CHANGE_ME"                                      # AD account allowed to join computers (sAMAccountName)
COMPUTER_OU="OU=Linux,OU=Servers,DC=ad,DC=example,DC=local" # target OU for the computer object ("" = default Computers)
LOGIN_GROUPS=("GG-AI-Users" "GG-AI-Admins")                # AD groups allowed to log in
SUDO_GROUP="GG-AI-Admins"                                  # AD group granted sudo ("" = none)
NTP_SERVERS="dc01.ad.example.local dc02.ad.example.local"  # NTP servers, normally the DCs
SHORT_NAMES="yes"                                          # yes = log in as 'bjorn', no = 'bjorn@domain'
GPO_ACCESS="permissive"                                    # ad_gpo_access_control (only used if access_provider=ad; 'realm permit' switches to simple)
TEST_USER=""                                               # optional AD user to verify with 'id' at the end
# =============================================================================

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

if [ "$(id -u)" -ne 0 ]; then exec sudo bash "$0" "$@"; fi

LOG=/var/log/gb10-adjoin.log
exec > >(tee -a "$LOG") 2>&1
echo; echo "===== gb10-adjoin.sh $(date '+%F %T') check-only=$CHECK_ONLY ====="

ok()   { printf '  [OK]   %s\n' "$*"; }
chg()  { printf '  [SET]  %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
die()  { printf '  [FAIL] %s\n' "$*"; exit 1; }

# --- 0. Parameter sanity ----------------------------------------------------
echo "0) Parameters"
[ "$JOIN_USER" = "CHANGE_ME" ] && die "JOIN_USER is not set - edit the PARAMETERS section"
[ "${#LOGIN_GROUPS[@]}" -gt 0 ] || die "LOGIN_GROUPS is empty - nobody would be able to log in"
case "$GPO_ACCESS" in enforcing|permissive|disabled) ;; *) die "GPO_ACCESS must be enforcing, permissive or disabled";; esac
ok "domain=$DOMAIN join_user=$JOIN_USER ou=${COMPUTER_OU:-<default>}"
ok "login groups: ${LOGIN_GROUPS[*]} | sudo group: ${SUDO_GROUP:-<none>}"

# --- 1. Pre-checks ----------------------------------------------------------
echo; echo "1) Pre-checks"
HN="$(hostname -s)"
[ "${#HN}" -le 15 ] && ok "hostname '$HN' (${#HN} chars, NetBIOS limit 15)" \
  || die "hostname '$HN' is longer than 15 characters - the computer account name would be truncated"
FQDN="$(hostname -f 2>/dev/null || true)"
[ "$FQDN" = "$HN.$DOMAIN" ] && ok "FQDN $FQDN" || warn "hostname -f returns '$FQDN', expected '$HN.$DOMAIN'"

if resolvectl query -t SRV "_ldap._tcp.dc._msdcs.$DOMAIN" >/tmp/adjoin-srv.txt 2>&1; then
  ok "DC SRV records found: $(grep -oE '[A-Za-z0-9.-]+\.'"${DOMAIN//./\\.}" /tmp/adjoin-srv.txt | sort -u | tr '\n' ' ')"
else
  cat /tmp/adjoin-srv.txt; die "cannot resolve _ldap._tcp.dc._msdcs.$DOMAIN - check DNS servers"
fi
resolvectl query "$FQDN" >/dev/null 2>&1 && ok "own A record resolves" || warn "own FQDN does not resolve in DNS"

if realm list 2>/dev/null | grep -qi "^$DOMAIN"; then
  ALREADY_JOINED=1; ok "already joined to $DOMAIN - join step will be skipped"
else
  ALREADY_JOINED=0; ok "not joined yet"
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo; echo "Check-only run finished. Nothing was changed."; exit 0
fi

# --- 2. Packages ------------------------------------------------------------
echo; echo "2) Packages"
PKGS=(realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin oddjob oddjob-mkhomedir packagekit krb5-user)
MISSING=()
for p in "${PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || MISSING+=("$p"); done
if [ "${#MISSING[@]}" -gt 0 ]; then
  export DEBIAN_FRONTEND=noninteractive        # avoid the krb5-user realm prompt
  apt-get update -qq
  apt-get install -y -qq "${MISSING[@]}"
  chg "installed: ${MISSING[*]}"
else
  ok "all packages present"
fi

# --- 3. Time sync against the DCs -------------------------------------------
echo; echo "3) Time synchronisation (Kerberos tolerates max 5 min skew)"
mkdir -p /etc/systemd/timesyncd.conf.d
TS=/etc/systemd/timesyncd.conf.d/10-ad.conf
printf '[Time]\nNTP=%s\n' "$NTP_SERVERS" > "$TS.new"
if cmp -s "$TS.new" "$TS" 2>/dev/null; then rm -f "$TS.new"; ok "$TS up to date"
else mv "$TS.new" "$TS"; chg "$TS (NTP=$NTP_SERVERS)"; fi
timedatectl set-ntp true
systemctl restart systemd-timesyncd
for i in $(seq 1 15); do
  [ "$(timedatectl show -p NTPSynchronized --value)" = "yes" ] && break; sleep 2
done
if [ "$(timedatectl show -p NTPSynchronized --value)" = "yes" ]; then
  ok "synchronised: $(timedatectl timesync-status 2>/dev/null | awk -F': ' '/Server|Offset/{printf "%s=%s ", $1, $2}' | tr -s ' ')"
else
  warn "not synchronised yet - the join may fail if the clock is more than 5 minutes off"
fi

# --- 4. Discover and join ---------------------------------------------------
echo; echo "4) Join $DOMAIN"
realm discover "$DOMAIN" | sed 's/^/  /'
if [ "$ALREADY_JOINED" -eq 0 ]; then
  OU_ARG=(); [ -n "$COMPUTER_OU" ] && OU_ARG=(--computer-ou="$COMPUTER_OU")
  echo "  You will be prompted for the password of $JOIN_USER"
  realm join --user="$JOIN_USER" "${OU_ARG[@]}" "$DOMAIN" </dev/tty
  chg "joined $DOMAIN"
fi
realm list | grep -q "configured: kerberos-member" && ok "realm: kerberos-member" || die "realm list does not show kerberos-member"

# --- 5. SSSD configuration --------------------------------------------------
echo; echo "5) SSSD configuration"
SSSD=/etc/sssd/sssd.conf
cp -p "$SSSD" "$SSSD.bak-$(date +%Y%m%d-%H%M%S)"
FQN="False"; HOMEDIR="/home/%u"
[ "$SHORT_NAMES" != "yes" ] && { FQN="True"; HOMEDIR="/home/%u@%d"; }
python3 -I - "$SSSD" "$FQN" "$HOMEDIR" "$GPO_ACCESS" <<'PY'
import configparser, sys
path, fqn, home, gpo = sys.argv[1:5]
cp = configparser.ConfigParser(interpolation=None)
cp.optionxform = str
cp.read(path)
sections = [s for s in cp.sections() if s.startswith("domain/")]
if not sections:
    sys.exit("no [domain/...] section in sssd.conf")
for s in sections:
    cp[s]["use_fully_qualified_names"] = fqn
    cp[s]["fallback_homedir"] = home
    cp[s]["ad_gpo_access_control"] = gpo
    print("  [SET]  [%s] use_fully_qualified_names=%s fallback_homedir=%s ad_gpo_access_control=%s" % (s, fqn, home, gpo))
with open(path, "w") as f:
    cp.write(f)
PY
chmod 600 "$SSSD"; chown root:root "$SSSD"
sssctl config-check >/dev/null 2>&1 && ok "sssctl config-check passed" || warn "sssctl config-check reported issues - see 'sssctl config-check'"

# --- 6. Home folders --------------------------------------------------------
echo; echo "6) Home folders on first login"
pam-auth-update --enable mkhomedir
ok "pam_mkhomedir enabled"

# --- 7. Login access --------------------------------------------------------
echo; echo "7) Login access"
realm deny --all
realm permit -g "${LOGIN_GROUPS[@]}"
ok "only these AD groups may log in: ${LOGIN_GROUPS[*]} (local accounts are not affected)"

# --- 8. Sudo ----------------------------------------------------------------
echo; echo "8) Sudo"
SUDOERS=/etc/sudoers.d/ad-sudo-group
if [ -n "$SUDO_GROUP" ]; then
  G="${SUDO_GROUP,,}"; G="${G// /\\ }"          # SSSD lowercases AD names; escape spaces for sudoers
  [ "$SHORT_NAMES" != "yes" ] && G="$G@${DOMAIN,,}"
  echo "%$G ALL=(ALL:ALL) ALL" > "$SUDOERS.tmp"
  chmod 440 "$SUDOERS.tmp"
  visudo -cf "$SUDOERS.tmp" >/dev/null || { rm -f "$SUDOERS.tmp"; die "generated sudoers entry is invalid"; }
  mv "$SUDOERS.tmp" "$SUDOERS"
  chg "$SUDOERS -> %$G ALL=(ALL:ALL) ALL"
else
  rm -f "$SUDOERS"; ok "no sudo group configured"
fi

# --- 9. Restart and verify --------------------------------------------------
echo; echo "9) Restart SSSD and verify"
systemctl restart sssd
sleep 3
systemctl is-active --quiet sssd && ok "sssd running" || die "sssd is not running - see 'journalctl -u sssd'"
realm list | sed 's/^/  /'
if [ -n "$TEST_USER" ]; then
  if id "$TEST_USER" >/dev/null 2>&1; then ok "id $TEST_USER: $(id "$TEST_USER")"
  else warn "id $TEST_USER failed - the user may not exist or SSSD is still starting (retry in a minute)"; fi
fi

echo
echo "===== Done. Log: $LOG"
echo "Test in a NEW terminal, keep this session open:"
echo "  ssh <ad-user>@$HN.$DOMAIN     then: sudo -v"
echo "Then add AD users to the AI stack:  sudo bash gb10-prepare.sh <ad-user1> <ad-user2>"
