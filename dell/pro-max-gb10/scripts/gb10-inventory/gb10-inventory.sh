#!/usr/bin/env bash
# gb10-inventory.sh - read-only inventory of a Dell Pro Max GB10 / DGX OS box.
# Changes nothing. Run with sudo for full output (other users' homes, logs, ports):
#   sudo bash gb10-inventory.sh
# Output: ./gb10-inventory-<host>-<date>.txt

OUT="gb10-inventory-$(hostname -s)-$(date +%Y%m%d-%H%M).txt"
exec > >(tee "$OUT") 2>&1

sec() { printf '\n==================== %s ====================\n' "$1"; }
run() { printf '\n$ %s\n' "$*"; eval "$@" 2>&1 || true; }
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(id -u)" -ne 0 ] && echo "NOTE: not running as root - some sections will be incomplete."

sec "1. OS / platform"
run "cat /etc/os-release"
run "cat /etc/dgx-release 2>/dev/null"
run "uname -a"
run "uptime"
run "hostnamectl 2>/dev/null | grep -v 'Machine ID\|Boot ID'"

sec "2. Hardware / GPU / CUDA"
run "lscpu | grep -E 'Model name|^CPU\(s\)|Architecture'"
run "free -h"
run "nvidia-smi"
run "nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv"
run "ls -d /usr/local/cuda* 2>/dev/null"
have nvcc && run "nvcc --version" || echo "nvcc not on PATH"

sec "3. Storage"
run "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE"
run "df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay"

sec "4. Network"
run "ip -br addr"
run "ip route"
run "resolvectl status 2>/dev/null | grep -E 'DNS Servers|DNS Domain' | sort -u"
have ibdev2netdev && run "ibdev2netdev"

sec "5. Listening ports (what is serving what)"
run "ss -tulpn | grep LISTEN"

sec "6. Update state"
run "apt list --upgradable 2>/dev/null | wc -l"
run "apt list --upgradable 2>/dev/null | grep -iE 'nvidia|cuda|dgx|kernel|linux-image' | head -40"
have fwupdmgr && run "fwupdmgr get-updates --no-unreported-check 2>/dev/null | head -40"

sec "7. Manually installed software (apt history = what your colleague did, with dates)"
run "zgrep -h -E '^(Start-Date|Commandline)' /var/log/apt/history.log* 2>/dev/null | grep -B1 Commandline | grep -v '^--' | tail -120"
run "dpkg -l | grep -iE 'nvidia-container|docker|containerd|cuda-toolkit|tensorrt|nccl' | awk '{print \$2, \$3}'"
have snap && run "snap list"
have pip3 && run "pip3 list 2>/dev/null | grep -iE 'vllm|torch|transformers|litellm|sglang|tensorrt|openai|huggingface'"

sec "8. Docker / containers"
if have docker; then
  run "docker version --format 'Client {{.Client.Version}} / Server {{.Server.Version}}'"
  run "docker info 2>/dev/null | grep -iE 'Runtimes|Default Runtime|Docker Root Dir|Storage Driver'"
  run "docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
  run "docker images --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}'"
  run "docker compose ls 2>/dev/null"
  run "docker volume ls"
  run "docker system df"
  # Where were compose files started from?
  run "docker ps -a -q | xargs -r docker inspect --format '{{.Name}} -> {{index .Config.Labels \"com.docker.compose.project.working_dir\"}} | restart={{.HostConfig.RestartPolicy.Name}}' 2>/dev/null"
else
  echo "docker not installed"
fi

sec "9. Inference stacks"
for b in ollama vllm llama-server llama-cli litellm trtllm-serve sglang open-webui uv conda jupyter; do
  if have "$b"; then echo "FOUND: $b -> $(command -v $b)"; else echo "not found: $b"; fi
done
have ollama && run "ollama --version; ollama list; ollama ps"
run "ps -eo pid,user,etime,rss,cmd --sort=-rss | grep -iE 'vllm|ollama|llama|litellm|sglang|trtllm|webui|python' | grep -v grep | head -20"

sec "10. Model storage (largest dirs)"
for d in /home/*/.cache/huggingface /root/.cache/huggingface /home/*/.ollama /usr/share/ollama/.ollama /opt /srv /data /models /var/lib/docker/volumes; do
  [ -d "$d" ] && du -sh "$d" 2>/dev/null
done
run "ls /home/*/.cache/huggingface/hub /root/.cache/huggingface/hub 2>/dev/null"

sec "11. Services and scheduled jobs"
run "systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print \$1}'"
run "systemctl list-unit-files --type=service --state=enabled --no-pager --no-legend | grep -iE 'nvidia|dgx|docker|ollama|vllm|litellm|webui|llama|jupyter|tailscale|ssh'"
run "ls /etc/systemd/system/*.service 2>/dev/null"
run "for u in \$(getent passwd | awk -F: '\$3>=1000 && \$3<65000{print \$1}'); do echo \"--- crontab \$u\"; crontab -l -u \$u 2>/dev/null; done"
run "ls /etc/cron.d"

sec "12. Users and access"
run "getent passwd | awk -F: '\$3>=1000 && \$3<65000 {print \$1, \$6, \$7}'"
run "getent group sudo docker"
run "for h in /root /home/*; do [ -f \$h/.ssh/authorized_keys ] && echo \"\$h: \$(wc -l < \$h/.ssh/authorized_keys) key(s): \$(awk '{print \$NF}' \$h/.ssh/authorized_keys | tr '\n' ' ')\"; done"
run "last -n 20 -w 2>/dev/null"

sec "13. Shell history (last commands per user - shows how far setup got)"
for h in /root /home/*; do
  [ -f "$h/.bash_history" ] && { echo "--- $h/.bash_history (last 80)"; tail -80 "$h/.bash_history"; }
done

sec "Done"
echo "Report written to: $(pwd)/$OUT"
echo "Review section 13 before sharing - shell history can contain tokens (HF_TOKEN etc.)."
