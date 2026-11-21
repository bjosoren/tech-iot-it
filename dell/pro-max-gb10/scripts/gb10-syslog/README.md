# gb10-syslog.sh

A Bash script that makes a **Dell Pro Max with GB10** (NVIDIA DGX OS / Ubuntu 24.04) a **syslog receiver for Omnissa Horizon Connection Server events**, so they can be analysed by the local LLM stack. Uses rsyslog, which is already installed and running on DGX OS.

![Bash](https://img.shields.io/badge/Bash-5%2B-blue)
![Idempotent](https://img.shields.io/badge/re--run-safe-green)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

Part of the blog series [Dell Pro Max GB10 – Building a local AI log analyzer](https://tech.iot-it.no/misc/dell-pro-max-gb10-local-ai-log-analysis/).

---

## What it does

- Listens on **UDP and TCP 5514** (IPv4 and IPv6)
- Writes **one file per sender per day**: `/srv/ai/logs/syslog/<sender>/YYYY-MM-DD.log`, group `aiops`, so the analyzer and the team can read them
- Keeps remote messages **out of `/var/log/syslog`** (dedicated rsyslog ruleset with `stop`)
- **Validates the config with `rsyslogd -N1` before restarting** – a broken config never takes down logging on the box
- Adds an **AppArmor** local override when the rsyslogd profile is enforced – otherwise rsyslog cannot write outside `/var/log`
- Only loads `imudp`/`imtcp` if the main config does not already load them
- **Retention**: a daily cron job deletes files older than 90 days
- Safe to re-run; the previous config is kept as a backup

---

## Requirements

- [`gb10-prepare.sh`](../gb10-prepare/) has been run (`/srv/ai`, `aiops` group)
- rsyslog running (default on DGX OS / Ubuntu)

---

## Usage

```bash
sudo bash gb10-syslog.sh --check    # show the config that would be written, change nothing
sudo bash gb10-syslog.sh            # configure and restart rsyslog
sudo bash gb10-syslog.sh --test     # send a UDP + TCP test message and show where it landed
```

Then in the Horizon Console: **Settings > Event Configuration > Syslog > Add** `<host>.<domain>:5514`. Horizon supports several syslog targets, so an existing target (e.g. ELK) can stay.

> Syslog is sent unencrypted. Use it on a trusted management network, and restrict senders with `ALLOWED_SENDERS` if needed.

---

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PORT` | `5514` | UDP and TCP port to listen on |
| `LOG_ROOT` | `/srv/ai/logs/syslog` | Where the per-sender folders are created |
| `AI_GROUP` | `aiops` | Group that owns the files |
| `RETENTION_DAYS` | `90` | Files older than this are deleted daily |
| `ALLOWED_SENDERS` | empty | e.g. `10.0.0.0/24` – empty accepts any sender that can reach the port |

---

## Notes

- What arrives are Horizon **events** (the same as the Events view in the console), not the Connection Server debug logs
- rsyslog wants file modes as octal with a leading zero: `dirCreateMode="02775"`, not `2775`

---

## License

MIT - see [LICENSE](LICENSE)

## Author

bjosoren - [tech.iot-it.no](https://tech.iot-it.no)
