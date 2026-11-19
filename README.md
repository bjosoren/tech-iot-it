# tech-iot-it

Public scripts, tools and automation published at [tech.iot-it.no](https://tech.iot-it.no).

This repository contains finished, anonymized, production-tested scripts covering the Omnissa (formerly VMware) Horizon stack, Microsoft, Linux, and general IT infrastructure automation. Each tool has its own folder with a README, usage examples and a LICENSE file.

All scripts are tried and tested in real environments. They are published here as a reference and starting point — adapt them to fit your own environment.

---

## Contents

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
├── vmware/
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
