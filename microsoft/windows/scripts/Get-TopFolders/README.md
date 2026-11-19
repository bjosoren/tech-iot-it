# Get-TopFolders.ps1

A PowerShell script that lists the largest folders on a drive (largest first, sizes in GB) and lets you **drill down** into any folder to see what's using the space beneath it.

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![No dependencies](https://img.shields.io/badge/dependencies-none-green)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

---

## What it does

- **Scans once, navigates instantly:** the drive (or `-Path`) is scanned one time and the size of every folder is kept in memory, so drilling down and going back up needs no rescans
- **Fast:** the scanner is a small embedded C# class (`Add-Type`), not `Get-ChildItem -Recurse`
- **Top N per level:** shows the largest subfolders of the current folder, plus the files lying directly in it, with size, percentage, file count and number of subfolders
- **Interactive navigation:** number = open that folder, `U` = up one level, `R` = back to the start, `Q` = quit
- **No double counting:** skips junctions and symlinks (e.g. `Documents and Settings`)
- **Includes hidden and system** folders and files
- **Honest about gaps:**
  - Folders that can't be read are skipped, counted, and marked with `*` in the list
  - Compares the scanned total with the drive's used space and tells you how much wasn't counted (pagefile, hiberfil, System Volume Information, shadow copies, unreadable folders)
  - Warns if not running as Administrator
- **Optional CSV export** of every scanned folder (path, depth, size, file count)

---

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 on Windows
- Run as **Administrator** for complete numbers (Windows, ProgramData, other users' profiles)

---

## Usage

### Interactive

Lists the drives, asks for a letter, scans, then lets you drill down:

```powershell
.\Get-TopFolders.ps1
```

### Specific drive, top 15 per level

```powershell
.\Get-TopFolders.ps1 -DriveLetter C -Top 15
```

### Start in a folder instead of a drive root

```powershell
.\Get-TopFolders.ps1 -Path C:\Windows
```

### Non-interactive with CSV export

```powershell
.\Get-TopFolders.ps1 -DriveLetter D -NoDrillDown -ExportCsv C:\Temp\d-folders.csv
```

### Example navigation (illustrative output)

```
C:\   (212.47 GB, 1,034,512 files)
  Top 10 of 18 subfolders

#  Folder        Size (GB) %    Files   Subdirs
-  ------        --------- -    -----   -------
1  Windows*      38.12     17.9 241,907 104
2  Users         35.80     16.8 188,422 6
3  Program Files 22.41     10.5 96,310  57
...

Open folder [1-10], U = up, R = start, Q = quit: 2
```

---

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-DriveLetter` | No | Drive to scan, e.g. `C` or `C:`. Prompted if neither this nor `-Path` is given |
| `-Path` | No | Scan a folder instead of a whole drive |
| `-Top` | No | Number of subfolders to show per level, 1–1000. Default `10` |
| `-NoDrillDown` | No | Show only the first list, no interactive navigation |
| `-ExportCsv` | No | Export every scanned folder (path, depth, size, files) to CSV, sorted by size |

---

## Notes

- Sizes are the logical file sizes (`FileInfo.Length`), not size on disk. Compressed, sparse and deduplicated files can therefore count higher than the space they actually use.
- The whole folder tree is held in memory. On drives with millions of folders this can use a noticeable amount of RAM.

---

## License

MIT - see [LICENSE](LICENSE)

## Author

bjosoren - [tech.iot-it.no](https://tech.iot-it.no)
