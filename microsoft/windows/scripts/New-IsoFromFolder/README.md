# New-IsoFromFolder.ps1

A PowerShell script that packages a folder into an **ISO file** using the IMAPI2 engine built into Windows. No oscdimg, no Windows ADK and no third-party tools required.

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![No dependencies](https://img.shields.io/badge/dependencies-none-green)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

Handy for getting drivers, installers or scripts into a VM through its virtual CD/DVD drive.

---

## What it does

- **ISO9660 + Joliet + UDF** image, so long file names and deep paths work
- **Folder contents go in the root** of the ISO. Use `-IncludeBaseFolder` to keep the folder itself as the top-level directory
- **Volume label** defaults to the folder name, cleaned to ISO-safe characters and cut to 16 characters
- **Sizes the image automatically:** DVD+R DL defaults (8.5 GB) for small folders, BD-R defaults above 8 GB
- **Progress bar** while writing, and a summary of file count, size, time and a `Mount-DiskImage` command to test the result
- **Safety checks:**
  - Refuses to create the ISO inside the folder being packaged
  - Asks before overwriting an existing ISO (unless `-Force`)
  - Warns about files of 4 GB or more
  - Removes a half-written ISO if writing fails
- **Data ISO only**, not bootable

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 on Windows
- IMAPI2 (`IMAPI2FS.MsftFileSystemImage`), included in desktop Windows and Windows Server with Desktop Experience. It may be missing on **Server Core**

---

## Usage

### Interactive (prompts for source folder and ISO path)

```powershell
.\New-IsoFromFolder.ps1
```

### With parameters

```powershell
.\New-IsoFromFolder.ps1 -SourceFolder C:\Temp\Drivers -IsoPath C:\ISO\Drivers.iso
```

### Custom label, overwrite existing

```powershell
.\New-IsoFromFolder.ps1 -SourceFolder D:\Install -IsoPath D:\ISO\Install.iso -VolumeName INSTALL -Force
```

### Test the result

```powershell
Mount-DiskImage -ImagePath C:\ISO\Drivers.iso
```

---

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-SourceFolder` | No* | Folder to package |
| `-IsoPath` | No* | ISO file to create. `.iso` is added if missing, and the target folder is created if needed |
| `-VolumeName` | No | ISO volume label. Default: the folder name (max 16 characters, `A-Z a-z 0-9 _ -`) |
| `-IncludeBaseFolder` | No | Put the folder itself in the ISO, not only its contents |
| `-Force` | No | Overwrite an existing ISO without asking |

\* Prompted interactively if not given.

---

## Limitations

- **Files of 4 GB or more:** ISO9660 and Joliet can't hold them. Such a file is only reachable through UDF, and IMAPI may refuse it altogether.
- **Not bootable:** the script creates data ISOs only.
- **Size:** the image is limited by the media type IMAPI is set up for (BD-R defaults above 8 GB).

---

## License

MIT - see [LICENSE](LICENSE)

## Author

bjosoren - [tech.iot-it.no](https://tech.iot-it.no)
