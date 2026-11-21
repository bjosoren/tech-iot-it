#!/usr/bin/env bash
# gb10-prepare.sh - prepare the shared AI stack layout on a Dell Pro Max GB10 (DGX OS).
#
# Creates /srv/ai with a shared group, a shared Hugging Face cache and a
# stack/.env template. Installs nothing and moves nothing. Safe to re-run.
#
# Usage (from your home folder):
#   sudo bash gb10-prepare.sh                     # adds you (the sudo caller) to the group
#   sudo bash gb10-prepare.sh kollega1 kollega2   # also adds these users
#   sudo bash gb10-prepare.sh --dry-run           # show what would happen
set -euo pipefail

AI_ROOT="/srv/ai"
AI_GROUP="aiops"
SUBDIRS=(stack models apps data logs)
DRY=0
EXTRA_USERS=()

for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) EXTRA_USERS+=("$a") ;;
  esac
done

# Re-run with sudo if needed
if [ "$(id -u)" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

CALLER="${SUDO_USER:-}"
if [ -z "$CALLER" ] || [ "$CALLER" = "root" ]; then
  echo "ERROR: run with sudo from your own user (not as root directly), so I know who to add." >&2
  exit 1
fi

ok()   { printf '  [OK]   %s\n' "$*"; }
chg()  { printf '  [NEW]  %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
do_()  { if [ "$DRY" -eq 1 ]; then printf '  [DRY]  %s\n' "$*"; else eval "$@"; fi; }

echo "== GB10 prepare: root=$AI_ROOT group=$AI_GROUP caller=$CALLER dry-run=$DRY"

# --- 1. Prerequisites (report only) ------------------------------------------
echo; echo "1) Prerequisites"
command -v nvidia-smi >/dev/null && ok "nvidia-smi present ($(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1))" \
  || warn "nvidia-smi missing - check the DGX OS installation"
if command -v docker >/dev/null; then
  ok "docker present ($(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'daemon not reachable'))"
  if docker info 2>/dev/null | grep -qi 'nvidia'; then
    ok "docker info reports NVIDIA ($(docker info 2>/dev/null | grep -i -m1 'nvidia' | sed 's/^ *//'))"
  elif command -v nvidia-ctk >/dev/null && nvidia-ctk cdi list 2>/dev/null | grep -q 'nvidia.com/gpu'; then
    ok "GPU exposed to containers via CDI ($(nvidia-ctk cdi list 2>/dev/null | grep -c 'nvidia.com/gpu') device entries)"
  else
    warn "no nvidia runtime and no CDI devices - check nvidia-container-toolkit"
  fi
else
  warn "docker missing - needed later for vLLM/LiteLLM"
fi
command -v setfacl >/dev/null && HAVE_ACL=1 || { HAVE_ACL=0; warn "setfacl missing (package 'acl') - falling back to setgid only"; }

# --- 2. Group and membership --------------------------------------------------
echo; echo "2) Group and membership"
if getent group "$AI_GROUP" >/dev/null; then ok "group $AI_GROUP exists"
else do_ "groupadd '$AI_GROUP'"; chg "group $AI_GROUP created"; fi

NEED_RELOGIN=()
for u in "$CALLER" "${EXTRA_USERS[@]}"; do
  if ! id "$u" >/dev/null 2>&1; then warn "user '$u' does not exist - skipped"; continue; fi
  for g in "$AI_GROUP" docker; do
    getent group "$g" >/dev/null || continue
    if id -nG "$u" | tr ' ' '\n' | grep -qx "$g"; then ok "$u is in $g"
    # gpasswd (not usermod) so it also works for AD/SSSD users that are not in /etc/passwd
    else do_ "gpasswd -a '$u' '$g' >/dev/null"; chg "$u added to $g"; NEED_RELOGIN+=("$u"); fi
  done
done

# --- 3. Directory structure ---------------------------------------------------
echo; echo "3) Directories under $AI_ROOT"
for d in "" "${SUBDIRS[@]}"; do
  p="$AI_ROOT/$d"; p="${p%/}"
  if [ -d "$p" ]; then ok "$p exists"
  else do_ "mkdir -p '$p'"; chg "$p"; fi
done
# Top-level dirs owned by root; below that keep file owners, only enforce the group
do_ "chown root:'$AI_GROUP' '$AI_ROOT' $(printf "'$AI_ROOT/%s' " "${SUBDIRS[@]}")"
do_ "chgrp -R '$AI_GROUP' '$AI_ROOT'"
do_ "find '$AI_ROOT' -type d -exec chmod 2775 {} +"
if [ "$HAVE_ACL" -eq 1 ]; then
  # Default ACL: group keeps write access regardless of each user's umask
  do_ "setfacl -R -m g:'$AI_GROUP':rwX '$AI_ROOT'"
  do_ "find '$AI_ROOT' -type d -exec setfacl -d -m g:'$AI_GROUP':rwX {} +"
  ok "permissions: root:$AI_GROUP, 2775 + default ACL"
else
  ok "permissions: root:$AI_GROUP, 2775 (setgid)"
fi

# --- 4. Environment for all login shells --------------------------------------
echo; echo "4) Environment (/etc/profile.d/ai-stack.sh)"
PROFILE=/etc/profile.d/ai-stack.sh
PROFILE_CONTENT="# Managed by gb10-prepare.sh
export AI_ROOT=$AI_ROOT
export HF_HOME=$AI_ROOT/models
umask 002"
if [ -f "$PROFILE" ] && [ "$(cat "$PROFILE")" = "$PROFILE_CONTENT" ]; then ok "$PROFILE up to date"
else
  if [ "$DRY" -eq 1 ]; then printf '  [DRY]  write %s\n' "$PROFILE"
  else printf '%s\n' "$PROFILE_CONTENT" > "$PROFILE"; chmod 644 "$PROFILE"; fi
  chg "$PROFILE (AI_ROOT, HF_HOME, umask 002)"
fi

# --- 5. stack/.env template (never overwritten) -------------------------------
echo; echo "5) $AI_ROOT/stack/.env"
ENVF="$AI_ROOT/stack/.env"
if [ -f "$ENVF" ]; then ok ".env exists - left untouched"
else
  KEY="sk-$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  if [ "$DRY" -eq 1 ]; then printf '  [DRY]  write %s\n' "$ENVF"
  else
    cat > "$ENVF" <<EOF
# Secrets and settings for the AI stack. NOT in git.
AI_ROOT=$AI_ROOT
HF_HOME=/models            # path inside containers; mount $AI_ROOT/models:/models
HF_TOKEN=                  # fill in if gated models are needed
LITELLM_MASTER_KEY=$KEY
EOF
    chown root:"$AI_GROUP" "$ENVF"; chmod 660 "$ENVF"
  fi
  chg ".env created (660 root:$AI_GROUP, generated LITELLM_MASTER_KEY)"
fi

# --- 6. README ----------------------------------------------------------------
README="$AI_ROOT/README.md"
if [ ! -f "$README" ] && [ "$DRY" -eq 0 ]; then
  cat > "$README" <<EOF
# /srv/ai - shared AI stack on $(hostname -s)
- stack/   compose.yaml, LiteLLM config, .env (secrets, not in git)
- models/  shared Hugging Face cache (HF_HOME)
- apps/    git clones of our own code (e.g. log-analyzer)
- data/    persistent data (vector store, volumes)
- logs/    incoming logs and service logs
Group: $AI_GROUP. Prepared $(date +%F) by $CALLER with gb10-prepare.sh.
EOF
  chown root:"$AI_GROUP" "$README"; chmod 664 "$README"
fi

# --- 7. Existing model caches (report only) -----------------------------------
echo; echo "7) Existing model caches outside $AI_ROOT (not moved)"
FOUND=0
for c in /root/.cache/huggingface /home/*/.cache/huggingface /home/*/.ollama /usr/share/ollama/.ollama; do
  [ -d "$c" ] || continue
  FOUND=1; printf '  %-45s %s\n' "$c" "$(du -sh "$c" 2>/dev/null | cut -f1)"
done
if [ "$FOUND" -eq 1 ]; then
  echo "  -> HF caches can be moved with:  sudo mv <path>/hub $AI_ROOT/models/  (same disk = instant)"
  echo "     Do that only after you have confirmed no running container is using them."
else ok "none found"; fi

# --- Summary ------------------------------------------------------------------
echo; echo "== Done."
if [ "${#NEED_RELOGIN[@]}" -gt 0 ]; then
  echo "   Log out and back in (or run 'newgrp $AI_GROUP') for: $(printf '%s\n' "${NEED_RELOGIN[@]}" | sort -u | tr '\n' ' ')"
fi
echo "   Check:  id; echo \$HF_HOME; ls -la $AI_ROOT"
