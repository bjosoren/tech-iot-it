# gb10-prepare.sh

A Bash script that prepares a **shared folder structure for a local AI stack** (vLLM, LiteLLM, own apps) on a Dell Pro Max with GB10 (NVIDIA DGX OS / Ubuntu 24.04): one root under `/srv/ai`, a dedicated group, a shared Hugging Face cache and a secrets template.

![Bash](https://img.shields.io/badge/Bash-5%2B-blue)
![Idempotent](https://img.shields.io/badge/re--run-safe-green)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

Part of the blog series [Dell Pro Max GB10 – Building a local AI log analyzer](https://tech.iot-it.no/misc/dell-pro-max-gb10-local-ai-log-analysis/).

---

## Why not the home folder?

- Services should not depend on a personal account
- More than one person works on the box
- Hugging Face caches models per user under `~/.cache/huggingface` by default – with two users the same 60–90 GB model easily ends up on disk twice

---

## What it does

```
/srv/ai/
├── stack/      # compose.yaml, LiteLLM config, .env (secrets, not in git)
├── models/     # HF_HOME – shared model cache for all users and containers
├── apps/       # git clones of own code
├── data/       # persistent data (vector store, volumes)
└── logs/       # incoming logs and service logs
```

- **Checks prerequisites** and reports: NVIDIA driver, Docker, and GPU access for containers through either the NVIDIA runtime or CDI
- Creates the group `aiops` and adds the calling user plus any users given as arguments to `aiops` and `docker`. Uses `gpasswd`, so it **works for AD/SSSD users** too
- Creates `/srv/ai` owned by `root:aiops` with setgid (2775) and **default ACLs**, so the group keeps write access regardless of each user's umask. On re-runs only the group is enforced – file owners are kept
- Writes `/etc/profile.d/ai-stack.sh` with `AI_ROOT`, `HF_HOME=/srv/ai/models` and `umask 002`
- Creates `stack/.env` (660) with a generated `LITELLM_MASTER_KEY` and an empty `HF_TOKEN`. **Never overwritten** on re-runs
- Lists existing model caches in home folders (not moved), so already downloaded models can be moved instead of downloaded again
- **Installs nothing and moves nothing.** Safe to re-run

---

## Requirements

- Ubuntu 24.04 / DGX OS 7
- `sudo`
- Optional: the `acl` package for default ACLs (falls back to setgid only)

---

## Usage

```bash
sudo bash gb10-prepare.sh --dry-run            # show what would happen
sudo bash gb10-prepare.sh                      # adds you (the sudo caller)
sudo bash gb10-prepare.sh <user1> <user2>      # also adds these users
```

Group membership takes effect at the next login. Then verify:

```bash
id; echo $HF_HOME; ls -la /srv/ai
docker ps                                      # works without sudo
```

> Membership in the `docker` group is effectively root on the box. Only add people who should have that level of access.

---

## License

MIT - see [LICENSE](LICENSE)

## Author

bjosoren - [tech.iot-it.no](https://tech.iot-it.no)
