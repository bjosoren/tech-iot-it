# Send-FileToDatastore.ps1

A PowerShell script that uploads a file, typically an ISO, to a **vSphere datastore** through vCenter's HTTPS file interface, using the `curl.exe` that ships with Windows. No PowerCLI required.

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![No dependencies](https://img.shields.io/badge/dependencies-none-green)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow)

Uploading large ISOs through the vSphere Client is slow and tends to fail on big files. Sending the file straight to vCenter's `/folder` endpoint with curl is faster and more robust.

---

## What it does

- Builds the vCenter datastore URL:
  ```
  https://<vcenter>/folder/<path>?dcPath=<datacenter>&dsName=<datastore>
  ```
  with every path segment, the datacenter and the datastore name URL-escaped (spaces and special characters are fine)
- Uploads with `curl.exe -T` and shows curl's progress meter
- **The password is prompted for by curl** and never stored or shown
- Shows elapsed time and throughput when done
- **Explains common failures** (wrong password, wrong datacenter or datastore name, missing target folder, untrusted certificate, DNS or connection problems)

---

## Requirements

- Windows 10 1803+ or Windows Server 2019+ (for the built-in `curl.exe`)
- Windows PowerShell 5.1 or PowerShell 7
- A vCenter account with datastore file permissions (Datastore > Low level file operations)
- HTTPS (443) to vCenter
- **The target folder on the datastore must already exist.** Create it in the vSphere Client datastore browser first

---

## Usage

```powershell
.\Send-FileToDatastore.ps1 -VCenter vc01.lab.local -Datacenter Datacenter -Datastore DS01 `
    -File D:\ISO\win11.iso -DatastorePath ISO/win11.iso
```

Different user, vCenter certificate not trusted by this machine:

```powershell
.\Send-FileToDatastore.ps1 -VCenter vc01.lab.local -Datacenter Datacenter -Datastore DS01 `
    -File D:\ISO\win11.iso -DatastorePath ISO/win11.iso -User admin@lab.local -SkipCertificateCheck
```

Without `-DatastorePath` the file goes to the root of the datastore with its own name.

---

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-VCenter` | Yes | vCenter FQDN |
| `-Datacenter` | Yes | Datacenter name exactly as shown in vCenter |
| `-Datastore` | Yes | Datastore name |
| `-File` | Yes | Local file to upload |
| `-DatastorePath` | No | Target path on the datastore, e.g. `ISO/win11.iso`. Default: the file name in the datastore root |
| `-User` | No | vCenter user. Default `administrator@vsphere.local` |
| `-SkipCertificateCheck` | No | Don't verify vCenter's certificate (`curl -k`). Prefer importing the vCenter root CA instead |

---

## The one-liner version

If you just want the bare command:

```powershell
$vc   = 'vc01.lab.local'
$dc   = 'Datacenter'
$ds   = 'DS01'
$dest = 'ISO/win11.iso'
$file = 'D:\ISO\win11.iso'

$uri = "https://$vc/folder/${dest}?dcPath=$([uri]::EscapeDataString($dc))&dsName=$([uri]::EscapeDataString($ds))"
curl.exe -u 'administrator@vsphere.local' -T $file $uri
```

Add `-k` only if the vCenter certificate isn't trusted.

---

## License

MIT - see [LICENSE](LICENSE)

## Author

bjosoren - [tech.iot-it.no](https://tech.iot-it.no)
