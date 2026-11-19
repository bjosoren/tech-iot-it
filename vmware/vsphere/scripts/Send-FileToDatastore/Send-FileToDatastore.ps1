<#
.SYNOPSIS
    Uploads a file (e.g. an ISO) to a vSphere datastore through vCenter's HTTPS file
    interface (/folder), using curl.exe. No PowerCLI needed.

.DESCRIPTION
    - Uses the vCenter datastore browser URL:
        https://<vcenter>/folder/<path>?dcPath=<datacenter>&dsName=<datastore>
    - curl.exe is built into Windows 10 1803+ / Windows Server 2019+
    - The password is prompted for by curl and never stored
    - Much faster and more reliable for large files than uploading through the vSphere Client
    - The target folder on the datastore must already exist

.PARAMETER VCenter
    vCenter FQDN.
.PARAMETER Datacenter
    Datacenter name exactly as shown in vCenter.
.PARAMETER Datastore
    Datastore name.
.PARAMETER DatastorePath
    Target path on the datastore, e.g. ISO/win11.iso. Default: the file name in the datastore root.
.PARAMETER File
    Local file to upload.
.PARAMETER User
    vCenter user. Default: administrator@vsphere.local.
.PARAMETER SkipCertificateCheck
    Don't verify vCenter's certificate (curl -k). Only use this if the vCenter certificate
    isn't trusted by this machine.

.EXAMPLE
    .\Send-FileToDatastore.ps1 -VCenter vc01.lab.local -Datacenter Datacenter -Datastore DS01 `
        -File D:\ISO\win11.iso -DatastorePath ISO/win11.iso

.EXAMPLE
    .\Send-FileToDatastore.ps1 -VCenter vc01.lab.local -Datacenter Datacenter -Datastore DS01 `
        -File D:\ISO\win11.iso -DatastorePath ISO/win11.iso -User admin@lab.local -SkipCertificateCheck

.NOTES
    Author : bjosoren - https://tech.iot-it.no
    License: MIT
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $VCenter,
    [Parameter(Mandatory)] [string] $Datacenter,
    [Parameter(Mandatory)] [string] $Datastore,
    [Parameter(Mandatory)] [string] $File,
    [string] $DatastorePath,
    [string] $User = 'administrator@vsphere.local',
    [switch] $SkipCertificateCheck
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw 'curl.exe not found. It is included in Windows 10 1803+ and Windows Server 2019+.'
}
if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "File not found: $File" }
$fileItem = Get-Item -LiteralPath $File

if (-not $DatastorePath) { $DatastorePath = $fileItem.Name }
$DatastorePath = $DatastorePath.Replace('\', '/').Trim('/')

# Escape each path segment (spaces, special characters), keep the slashes
$escapedPath = ($DatastorePath -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
$uri = "https://$VCenter/folder/$($escapedPath)?dcPath=$([uri]::EscapeDataString($Datacenter))&dsName=$([uri]::EscapeDataString($Datastore))"

Write-Host "File      : $($fileItem.FullName) ($('{0:N2}' -f ($fileItem.Length / 1GB)) GB)" -ForegroundColor Cyan
Write-Host "Target    : [$Datastore] $DatastorePath  (datacenter '$Datacenter')"          -ForegroundColor Cyan
Write-Host "vCenter   : $VCenter as $User"                                                -ForegroundColor Cyan
Write-Host ''

$curlArgs = @('--fail', '--show-error', '-u', $User, '-T', $fileItem.FullName, $uri, '-o', 'NUL')
if ($SkipCertificateCheck) { $curlArgs = @('-k') + $curlArgs }

$sw = [Diagnostics.Stopwatch]::StartNew()
& curl.exe @curlArgs
$exit = $LASTEXITCODE
$sw.Stop()

if ($exit -ne 0) {
    $hint = switch ($exit) {
        22 { 'HTTP error. 401 = wrong user/password, 404 = wrong datacenter/datastore name or the target folder does not exist.' }
        60 { 'Certificate not trusted. Import the vCenter root CA, or use -SkipCertificateCheck.' }
        6  { 'Could not resolve the vCenter name.' }
        7  { 'Could not connect to vCenter on port 443.' }
        default { 'See the curl error above.' }
    }
    throw "Upload failed (curl exit code $exit). $hint"
}

$mbps = if ($sw.Elapsed.TotalSeconds -gt 0) { $fileItem.Length / 1MB / $sw.Elapsed.TotalSeconds } else { 0 }
Write-Host ''
Write-Host ('Uploaded in {0:N0} s ({1:N0} MB/s): [{2}] {3}' -f $sw.Elapsed.TotalSeconds, $mbps, $Datastore, $DatastorePath) -ForegroundColor Green
