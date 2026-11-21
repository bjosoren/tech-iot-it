# tech-iot-it

Public scripts, tools and automation published at [tech.iot-it.no](https://tech.iot-it.no).

This repository contains finished, anonymized, production-tested scripts covering the Omnissa (formerly VMware) Horizon stack, Microsoft, Linux, and general IT infrastructure automation. Each tool has its own folder with a README, usage examples and a LICENSE file.

All scripts are tried and tested in real environments. They are published here as a reference and starting point — adapt them to fit your own environment.

---

## Contents

### Windows

| Script | Description | Blog post |
|--------|-------------|-----------|
| [Get-TopFolders](microsoft/windows/scripts/Get-TopFolders/) | Lists the largest folders on a drive and lets you drill down interactively. One fast scan, then instant navigation | – |
| [New-IsoFromFolder](microsoft/windows/scripts/New-IsoFromFolder/) | Packages a folder into an ISO file (ISO9660 + Joliet + UDF) with the IMAPI2 engine built into Windows. No ADK or extra tools | – |

### VMware vSphere

| Script | Description | Blog post |
|--------|-------------|-----------|
| [Send-FileToDatastore](vmware/vsphere/scripts/Send-FileToDatastore/) | Uploads a file (e.g. an ISO) to a datastore through vCenter's HTTPS file interface with the built-in curl.exe. No PowerCLI | – |

### Dell Pro Max with GB10 (NVIDIA DGX OS)

| Script | Description | Blog post |
|--------|-------------|-----------|
| [gb10-inventory](dell/pro-max-gb10/scripts/gb10-inventory/) | Read-only inventory of a GB10 / DGX OS box: versions, updates, Docker, inference stacks, models, ports, services, users and shell history in one report | [Local AI log analyzer](https://tech.iot-it.no/misc/dell-pro-max-gb10-local-ai-log-analysis/) |
| [gb10-adjoin](dell/pro-max-gb10/scripts/gb10-adjoin/) | Joins the box to Active Directory with realmd/SSSD, restricts logins to AD groups and grants sudo to an AD group. Parameters at the top, safe to re-run | [Local AI log analyzer](https://tech.iot-it.no/misc/dell-pro-max-gb10-local-ai-log-analysis/) |
| [gb10-prepare](dell/pro-max-gb10/scripts/gb10-prepare/) | Shared `/srv/ai` structure for a local AI stack: dedicated group, default ACLs, shared Hugging Face cache and a secrets template | [Local AI log analyzer](https://tech.iot-it.no/misc/dell-pro-max-gb10-local-ai-log-analysis/) |
| [gb10-stack](dell/pro-max-gb10/scripts/gb10-stack/) | Deploys vLLM (NVIDIA NGC container) and LiteLLM with Docker Compose as a local, OpenAI-compatible endpoint for log analysis, with a JSON-schema smoke test | [Local AI log analyzer](https://tech.iot-it.no/misc/dell-pro-max-gb10-local-ai-log-analysis/) |
| [gb10-syslog](dell/pro-max-gb10/scripts/gb10-syslog/) | Makes the box a syslog receiver (rsyslog, UDP/TCP 5514) for Horizon Connection Server events, one file per sender per day, with config validation, AppArmor override and retention | [Local AI log analyzer](https://tech.iot-it.no/misc/dell-pro-max-gb10-local-ai-log-analysis/) |

### Omnissa

Omnissa scripts (Horizon, App Volumes, DEM, UAG) are published in their own repository, [bjosoren/omnissa](https://github.com/bjosoren/omnissa), under `operations/<product>/scripts/`. For example:

| Script | Location |
|--------|----------|
| Get-DEMShareReport | [omnissa/operations/dem/scripts/Get-DEMShareReport](https://github.com/bjosoren/omnissa/tree/main/operations/dem/scripts/Get-DEMShareReport) |

---

## Structure

```
tech-iot-it/
├── microsoft/
│   └── windows/
│       └── scripts/
│           ├── Get-TopFolders/
│           └── New-IsoFromFolder/
├── vmware/
│   └── vsphere/
│       └── scripts/
│           └── Send-FileToDatastore/
├── dell/
│   └── pro-max-gb10/
│       └── scripts/
│           ├── gb10-inventory/
│           ├── gb10-adjoin/
│           ├── gb10-prepare/
│           ├── gb10-stack/
│           └── gb10-syslog/
└── linux/
```

New tools are added as they are published on the blog.

---

## Usage

Each tool folder contains its own `README.md` with full usage instructions and parameter documentation. Clone the repo or download individual scripts directly from GitHub.

```powershell
# Example: clone the full repo
git clone https://github.com/bjosoren/tech-iot-it.git
```

---

## License

All scripts in this repository are published under the MIT License unless otherwise stated in the individual tool folder. See [LICENSE](LICENSE).

## Author

bjosoren — [tech.iot-it.no](https://tech.iot-it.no)
