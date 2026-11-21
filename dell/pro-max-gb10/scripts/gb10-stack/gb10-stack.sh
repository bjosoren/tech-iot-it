#!/usr/bin/env bash
# gb10-stack.sh - deploy and manage the local LLM stack for log analysis on a Dell Pro Max GB10
#
#   vLLM    (NVIDIA NGC container)  - inference, internal only (127.0.0.1:8000 for debugging)
#   LiteLLM (OpenAI-compatible API) - the endpoint clients use: http://<host>:4000/v1
#                                      model alias "log-analyzer"
#
# Requires gb10-prepare.sh to have been run (/srv/ai, aiops group, stack/.env).
#
# Usage:
#   bash gb10-stack.sh deploy    # write compose/config (only if missing), pull images, start
#   bash gb10-stack.sh status    # containers, health, models
#   bash gb10-stack.sh test      # log-analysis smoke test with structured (JSON schema) output
#   bash gb10-stack.sh logs      # follow vLLM logs (first start downloads model + compiles)
#   bash gb10-stack.sh down      # stop the stack
#   bash gb10-stack.sh deploy --force   # overwrite compose.yaml/config.yaml (backups are kept)
set -euo pipefail

# ============================== PARAMETERS ===================================
AI_ROOT="/srv/ai"
STACK="$AI_ROOT/stack"
# Model and container from NVIDIA's validated DGX Spark 128 GB recipe (Qwen3.8 27B NVFP4)
VLLM_IMAGE="nvcr.io/nvidia/vllm:26.10.pre1-py3"
MODEL="nvidia/Qwen3.8-27B-NVFP4"
DRAFT_MODEL="z-lab/Qwen3.8-27B-DFlash2"          # speculative decoding draft model
MAX_MODEL_LEN=262144                             # long context - room for large log excerpts
GPU_MEM_UTIL=0.60                                # as in NVIDIA's recipe
LITELLM_IMAGE="ghcr.io/berriai/litellm:main-stable"
LITELLM_PORT=4000
MODEL_ALIAS="log-analyzer"                       # the name clients ask for
# =============================================================================

CMD="${1:-}"; FORCE=0; [ "${2:-}" = "--force" ] && FORCE=1
ok()   { printf '  [OK]   %s\n' "$*"; }
chg()  { printf '  [NEW]  %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
die()  { printf '  [FAIL] %s\n' "$*"; exit 1; }
dc()   { docker compose --project-directory "$STACK" -f "$STACK/compose.yaml" "$@"; }

prechecks() {
  [ -d "$STACK" ] || die "$STACK missing - run gb10-prepare.sh first"
  [ -r "$STACK/.env" ] || die "cannot read $STACK/.env - are you in the aiops group (log out/in after gb10-prepare.sh)?"
  docker ps >/dev/null 2>&1 || die "cannot talk to docker - are you in the docker group?"
  grep -q '^LITELLM_MASTER_KEY=sk-' "$STACK/.env" || die "LITELLM_MASTER_KEY missing in $STACK/.env"
}

write_file() {   # write_file <path> <content> - only if missing, or with --force (backup kept)
  local path="$1" content="$2"
  if [ -f "$path" ] && [ "$FORCE" -eq 0 ]; then
    if [ "$(cat "$path")" = "$content" ]; then ok "$path up to date"
    else warn "$path exists and differs - kept (use 'deploy --force' to overwrite)"; fi
    return
  fi
  [ -f "$path" ] && cp -p "$path" "$path.bak-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  chg "$path"
}

compose_yaml() { cat <<EOF
# Managed by gb10-stack.sh - local LLM stack for log analysis
name: ai-stack

services:
  vllm:
    image: $VLLM_IMAGE
    container_name: vllm
    restart: unless-stopped
    entrypoint: []                       # ignore the image entrypoint, as in NVIDIA's recipe
    command:
      - vllm
      - serve
      - $MODEL
      - --host=0.0.0.0
      - --port=8000
      - --served-model-name=$MODEL
      - --kv-cache-dtype=fp8
      - --max-model-len=$MAX_MODEL_LEN
      - --max-num-seqs=8
      - --async-scheduling
      - --enable-flashinfer-autotune
      - --gpu-memory-utilization=$GPU_MEM_UTIL
      - '--kernel-config={"linear_backend":"nvfp4_dynamic","nvfp4_dynamic_max_tokens":16,"unquantized_linear_backend":"flashinfer_cudnn","linear_backend_per_quant":{"fp8_w8a8":"cutlass"}}'
      - '--speculative-config={"method":"dflash","model":"$DRAFT_MODEL","num_speculative_tokens":7,"draft_sample_method":"probabilistic","rejection_sample_method":"standard"}'
      - '--compilation-config={"pass_config":{"fuse_act_quant":true},"max_cudagraph_capture_size":64}'
      - --reasoning-parser=qwen3
      - --tool-call-parser=qwen3_xml
      - --enable-auto-tool-choice
      - --enable-prefix-caching          # same system prompt on every log analysis call
    environment:
      HF_HOME: /models
      HF_TOKEN: \${HF_TOKEN:-}
    volumes:
      - $AI_ROOT/models:/models
    ports:
      - "127.0.0.1:8000:8000"           # local debugging only - clients go through LiteLLM
    ipc: host
    shm_size: 16g
    ulimits:
      memlock: -1
      stack: 67108864
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    healthcheck:
      test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=4)"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 45m                  # first start: model download + autotune + compile

  litellm:
    image: $LITELLM_IMAGE
    container_name: litellm
    restart: unless-stopped
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    environment:
      LITELLM_MASTER_KEY: \${LITELLM_MASTER_KEY}
    volumes:
      - ./litellm/config.yaml:/app/config.yaml:ro
    ports:
      - "0.0.0.0:$LITELLM_PORT:4000"
    depends_on:
      vllm:
        condition: service_healthy
EOF
}

litellm_config() { cat <<EOF
# Managed by gb10-stack.sh - clients call the alias, never the backend model name
model_list:
  - model_name: $MODEL_ALIAS
    litellm_params:
      model: hosted_vllm/$MODEL
      api_base: http://vllm:8000/v1
      api_key: none
      timeout: 600
  - model_name: qwen3.8-27b
    litellm_params:
      model: hosted_vllm/$MODEL
      api_base: http://vllm:8000/v1
      api_key: none
      timeout: 600

litellm_settings:
  drop_params: true

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
EOF
}

deploy() {
  echo "== Deploy"; prechecks
  write_file "$STACK/compose.yaml" "$(compose_yaml)"
  write_file "$STACK/litellm/config.yaml" "$(litellm_config)"
  df -h "$AI_ROOT" | awk 'NR==2{print "  [OK]   free space on "$6": "$4}'
  echo "  Pulling images (the vLLM image is large)..."
  dc pull
  dc up -d
  ok "stack started"
  echo
  echo "First start downloads the model and draft model into $AI_ROOT/models and"
  echo "runs autotuning/compilation - this can take a long time. Follow with:"
  echo "  bash $0 logs      (ready when you see 'Application startup complete')"
  echo "  bash $0 status"
}

status() {
  echo "== Status"; prechecks
  dc ps
  echo
  if curl -fsS -m 5 http://127.0.0.1:8000/health >/dev/null 2>&1; then ok "vLLM healthy"
  else warn "vLLM not ready yet (still starting?)"; fi
  local key; key="$(grep '^LITELLM_MASTER_KEY=' "$STACK/.env" | cut -d= -f2-)"
  if models="$(curl -fsS -m 5 -H "Authorization: Bearer $key" "http://127.0.0.1:$LITELLM_PORT/v1/models" 2>/dev/null)"; then
    ok "LiteLLM models: $(printf '%s' "$models" | python3 -c 'import sys,json;print(", ".join(m["id"] for m in json.load(sys.stdin)["data"]))')"
  else warn "LiteLLM not answering on :$LITELLM_PORT yet (it waits for vLLM to be healthy)"; fi
  du -sh "$AI_ROOT/models" 2>/dev/null | awk '{print "  [OK]   model cache: "$1}'
}

smoke_test() {
  echo "== Log-analysis smoke test (via LiteLLM, alias '$MODEL_ALIAS', JSON schema output)"; prechecks
  local key; key="$(grep '^LITELLM_MASTER_KEY=' "$STACK/.env" | cut -d= -f2-)"
  python3 -I - "$key" "$LITELLM_PORT" "$MODEL_ALIAS" <<'PY'
import json, sys, time, urllib.request
key, port, alias = sys.argv[1:4]
log = """2026-11-21T10:02:11.412+01:00 INFO  (pool-12) [VCHealthUpdate] vCenter vc01.lab.local status: STATUS_UP
2026-11-21T10:04:37.008+01:00 ERROR (InstantCloneOps-3) [ProvisionTask] Pool 'W11-Desktops': failed to create clone W11-Desk-014: Fault cause: vim.fault.NoDiskSpace - Insufficient disk space on datastore 'DS-VDI-01'
2026-11-21T10:04:37.115+01:00 WARN  (InstantCloneOps-3) [ProvisionTask] Pool 'W11-Desktops': provisioning error count 3, pool provisioning will be disabled after 5 errors
2026-11-21T10:05:02.731+01:00 ERROR (InstantCloneOps-1) [ProvisionTask] Pool 'W11-Desktops': failed to create clone W11-Desk-015: Fault cause: vim.fault.NoDiskSpace - Insufficient disk space on datastore 'DS-VDI-01'
2026-11-21T10:05:40.220+01:00 INFO  (pool-12) [DesktopTracker] Pool 'RDSH-GPU' available sessions: 18/40"""
schema = {"type": "object", "additionalProperties": False,
  "required": ["status", "summary", "findings"],
  "properties": {
    "status": {"type": "string", "enum": ["ok", "warning", "error"]},
    "summary": {"type": "string"},
    "findings": {"type": "array", "items": {"type": "object", "additionalProperties": False,
      "required": ["severity", "component", "issue", "likely_cause", "next_step"],
      "properties": {
        "severity": {"type": "string", "enum": ["info", "warning", "error"]},
        "component": {"type": "string"}, "issue": {"type": "string"},
        "likely_cause": {"type": "string"}, "next_step": {"type": "string"}}}}}}
body = {"model": alias, "max_tokens": 4096, "temperature": 0.2,
  "messages": [
    {"role": "system", "content": "You analyse Omnissa Horizon / App Volumes logs after automated maintenance runs. Be precise and brief. Only report what the log supports."},
    {"role": "user", "content": "Analyse this log excerpt:\n\n" + log}],
  "response_format": {"type": "json_schema", "json_schema": {"name": "log_analysis", "strict": True, "schema": schema}}}
req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions", data=json.dumps(body).encode(),
  headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
t = time.time()
try:
    resp = json.load(urllib.request.urlopen(req, timeout=600))
except Exception as e:
    sys.exit(f"  [FAIL] request failed: {e}")
dt = time.time() - t
content = resp["choices"][0]["message"]["content"]
usage = resp.get("usage", {})
try:
    result = json.loads(content)
except json.JSONDecodeError:
    print(content); sys.exit("  [FAIL] response was not valid JSON")
print(json.dumps(result, indent=2, ensure_ascii=False))
toks = usage.get("completion_tokens", 0)
print(f"\n  [OK]   valid JSON matching the schema | {dt:.1f}s | prompt {usage.get('prompt_tokens','?')} / completion {toks} tokens"
      + (f" | ~{toks/dt:.0f} tok/s incl. reasoning" if toks and dt else ""))
PY
}

case "$CMD" in
  deploy) deploy ;;
  status) status ;;
  test)   smoke_test ;;
  logs)   prechecks; dc logs -f --tail 100 vllm ;;
  down)   prechecks; dc down; ok "stack stopped" ;;
  *) sed -n '2,17p' "$0"; exit 1 ;;
esac
