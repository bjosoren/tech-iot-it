# tech-iot-it

Public scripts, tools and automation published at [tech.iot-it.no](https://tech.iot-it.no).

This repository contains finished, anonymized, production-tested scripts covering the Omnissa (formerly VMware) Horizon stack, Microsoft, Linux, and general IT infrastructure automation. Each tool has its own folder with a README, usage examples and a LICENSE file.

All scripts are tried and tested in real environments. They are published here as a reference and starting point — adapt them to fit your own environment.

---

## Contents

### Omnissa

| Script | Description | Blog post |
|--------|-------------|-----------|
| [Get-DEMShareReport](omnissa/dem/Get-DEMShareReport/) | Generates a styled HTML documentation report for Omnissa DEM file shares — SMB permissions, NTFS ACLs, folder ownership and subfolder structure | [tech.iot-it.no](https://tech.iot-it.no) |

---

## Structure

```
tech-iot-it/
├── omnissa/
│   ├── dem/
│   │   └── Get-DEMShareReport/
│   ├── appvolumes/
│   └── horizon/
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
