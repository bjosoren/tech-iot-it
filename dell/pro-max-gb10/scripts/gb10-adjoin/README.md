# gb10-adjoin.sh

A Bash script that joins a **Dell Pro Max with GB10** (NVIDIA DGX OS / Ubuntu 24.04) to **Active Directory** with realmd and SSSD, restricts logins to AD groups and grants sudo to an AD group. All values are parameters at the top of the script.

![Bash](https://img.shields.io/badge/Bash-5%2B-blue)
![Idempotent](https://img.shields.io/badge/re--run-safe-green)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

Part of the blog series [Dell Pro Max GB10 – Building a local AI log analyzer](https://tech.iot-it.no/misc/dell-pro-max-gb10-local-ai-log-analysis/).

---

## What it does

- **Pre-checks:** hostname length (NetBIOS limit of 15 characters), FQDN, DC SRV records in DNS, existing join
- Installs `realmd`, `sssd`, `adcli` and friends non-interactively (no krb5-user realm prompt)
- **Syncs time against the DCs** through a `timesyncd` drop-in – Kerberos tolerates at most 5 minutes of clock skew
- Joins the domain into the given OU. **The password is prompted for** and never stored
- Configures SSSD for short user names (`bjorn` instead of `bjorn@domain`) and `/home/<user>`, backing up `sssd.conf` first
- Creates home folders on first login (`pam_mkhomedir`)
- **Restricts logins** to the given AD groups (`realm deny --all` + `realm permit -g`). Local accounts are not affected
- **Grants sudo** to an AD group through `/etc/sudoers.d`, validated with `visudo` before it is installed. Handles lowercasing and group names with spaces
- Restarts SSSD and verifies the result
- **Safe to re-run:** if already joined, the join is skipped and the configuration re-applied
- Logs to `/var/log/gb10-adjoin.log`

---

## Requirements

- Ubuntu 24.04 / DGX OS 7 with a static IP and DNS pointing at the domain controllers
- Correct hostname and FQDN (`hostname -f` = `<host>.<domain>`)
- In AD:
  - Two groups – who may log in, and who gets sudo (e.g. `GG-AI-Users`, `GG-AI-Admins`)
  - An OU for the computer object and an account allowed to join computers to it

---

## Usage

1. Edit the `PARAMETERS` section at the top of the script
2. Run the pre-checks, then the full run:

```bash
sudo bash gb10-adjoin.sh --check     # pre-checks only, changes nothing
sudo bash gb10-adjoin.sh             # full run, prompts for the join password
```

3. Test in a **new** terminal and keep the existing session open until it works:

```bash
ssh <ad-user>@<host>.<domain>
id                                   # AD groups listed
sudo -v                              # works for members of the sudo group
```

Keep a local admin account as break-glass in case SSSD or the DCs are unreachable.

---

## Parameters

| Parameter | Description |
|-----------|-------------|
| `DOMAIN` | AD DNS domain, e.g. `ad.example.local` |
| `JOIN_USER` | AD account allowed to join computers. The script refuses to run while it is `CHANGE_ME` |
| `COMPUTER_OU` | Target OU for the computer object. `""` = default `CN=Computers` |
| `LOGIN_GROUPS` | Bash array of AD groups allowed to log in |
| `SUDO_GROUP` | AD group granted sudo. `""` = none |
| `NTP_SERVERS` | NTP servers, normally the domain controllers |
| `SHORT_NAMES` | `yes` = log in as `user`, `no` = `user@domain` |
| `GPO_ACCESS` | SSSD `ad_gpo_access_control`. Only relevant if access is not restricted with `realm permit` |
| `TEST_USER` | Optional AD user to verify with `id` at the end |

---

## Notes

- To add AD users to local groups afterwards, use `gpasswd -a <user> <group>` – `usermod -aG` only works for users in `/etc/passwd`
- If Tailscale is installed, make sure it has not taken over DNS (`sudo tailscale set --accept-dns=false`)

---

## License

MIT - see [LICENSE](LICENSE)

## Author

bjosoren - [tech.iot-it.no](https://tech.iot-it.no)
