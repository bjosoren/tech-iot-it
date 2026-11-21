# gb10-inventory.sh

A read-only Bash script that takes a complete **inventory of a Dell Pro Max with GB10** (NVIDIA DGX OS / Ubuntu 24.04) and writes everything to one report file. Useful when someone else did the initial setup and you need to know how far they got before you build anything on top.

![Bash](https://img.shields.io/badge/Bash-5%2B-blue)
![Read-only](https://img.shields.io/badge/changes-none-green)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

Part of the blog series [Dell Pro Max GB10 – Building a local AI log analyzer](https://tech.iot-it.no/misc/dell-pro-max-gb10-local-ai-log-analysis/).

---

## What it does

Collects, in 13 sections:

1. OS and platform (`/etc/os-release`, `/etc/dgx-release`, kernel, firmware)
2. CPU, memory, GPU, driver and CUDA versions
3. Storage (disks, partitions, free space)
4. Network interfaces, routes, DNS
5. Listening ports – what is actually running
6. Pending package and firmware updates
7. **apt history** – every manually installed package, with dates
8. Docker – containers, images, volumes, restart policies, compose working directories
9. Inference stacks (Ollama, vLLM, llama.cpp, LiteLLM, SGLang, TensorRT-LLM, Open WebUI …)
10. Model storage (Hugging Face and Ollama caches, Docker volumes)
11. Running and enabled services, cron jobs
12. Users, sudo/docker group members, SSH keys, recent logins
13. **Shell history** per user – usually shows exactly where the setup stopped

It **changes nothing** on the system.

---

## Requirements

- Dell Pro Max with GB10 / NVIDIA DGX Spark running DGX OS 7 (works on any Ubuntu 24.04 box, GPU sections are simply empty)
- `sudo` for complete output (other users' homes, apt logs, process owners of listening ports)

---

## Usage

```bash
scp gb10-inventory.sh <user>@<gb10-host>:~
ssh <user>@<gb10-host>
sudo bash gb10-inventory.sh
```

Output: `gb10-inventory-<host>-<yyyymmdd-hhmm>.txt` in the current folder (also shown on screen).

> **Review section 13 before sharing the report.** Shell history often contains tokens such as `HF_TOKEN` in clear text.

If you get `$'\r': command not found`, the file picked up Windows line endings on the way. Fix with:

```bash
sed -i 's/\r$//' gb10-inventory.sh
```

---

## License

MIT - see [LICENSE](LICENSE)

## Author

bjosoren - [tech.iot-it.no](https://tech.iot-it.no)
