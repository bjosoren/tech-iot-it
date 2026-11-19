<#
.SYNOPSIS
    Packages a folder into an ISO file using the IMAPI2 engine built into Windows.

.DESCRIPTION
    - No extra tools needed (no oscdimg/ADK, no 3rd-party software)
    - Creates an ISO9660 + Joliet + UDF image, so long file names and deep paths work
    - The folder's contents end up in the root of the ISO (use -IncludeBaseFolder to keep
      the folder itself as the top-level directory)
    - Works in Windows PowerShell 5.1 and PowerShell 7 on Windows
    - Data ISO only (not bootable)

.EXAMPLE
    .\New-IsoFromFolder.ps1
    # prompts for source folder and ISO path

.EXAMPLE
    .\New-IsoFromFolder.ps1 -SourceFolder C:\Temp\Drivers -IsoPath C:\ISO\Drivers.iso

.EXAMPLE
    .\New-IsoFromFolder.ps1 -SourceFolder D:\Install -IsoPath D:\ISO\Install.iso -VolumeName INSTALL -Force
#>
[CmdletBinding()]
param(
    [string] $SourceFolder,
    [string] $IsoPath,
    [string] $VolumeName,          # ISO volume label, default = folder name (max 16 chars)
    [switch] $IncludeBaseFolder,   # put the folder itself in the ISO instead of only its contents
    [switch] $Force                # overwrite an existing ISO
)

$ErrorActionPreference = 'Stop'

# ---------- Input ----------
if (-not $SourceFolder) { $SourceFolder = Read-Host 'Folder to package' }
if (-not $IsoPath)      { $IsoPath      = Read-Host 'ISO file to create (path\name.iso)' }
$SourceFolder = $SourceFolder.Trim().Trim('"')
$IsoPath      = $IsoPath.Trim().Trim('"')

if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) { throw "Folder not found: $SourceFolder" }
$SourceFolder = (Resolve-Path -LiteralPath $SourceFolder).Path.TrimEnd('\')

if ([IO.Path]::GetExtension($IsoPath) -ne '.iso') { $IsoPath += '.iso' }
$IsoPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($IsoPath)
$isoDir  = Split-Path -Parent $IsoPath
if (-not (Test-Path -LiteralPath $isoDir)) { New-Item -ItemType Directory -Path $isoDir -Force | Out-Null }

if ($IsoPath.StartsWith($SourceFolder + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The ISO file cannot be created inside the folder being packaged.'
}
if ((Test-Path -LiteralPath $IsoPath) -and -not $Force) {
    $ow = Read-Host "$IsoPath already exists. Overwrite? (y/N)"
    if ($ow -notmatch '^[Yy]') { Write-Host 'Aborted.'; return }
    $Force = $true
}

# Volume label: ISO/Joliet-safe characters, max 16
if (-not $VolumeName) { $VolumeName = Split-Path -Leaf $SourceFolder }
$VolumeName = ($VolumeName -replace '[^A-Za-z0-9_\-]', '_')
if ($VolumeName.Length -gt 16) { $VolumeName = $VolumeName.Substring(0, 16) }
if (-not $VolumeName) { $VolumeName = 'DATA' }

# ---------- Source summary ----------
Write-Host 'Calculating source size...' -ForegroundColor DarkGray
$files = Get-ChildItem -LiteralPath $SourceFolder -Recurse -File -Force -ErrorAction SilentlyContinue
$stats = $files | Measure-Object Length -Sum -Maximum
$totalBytes = [long]$stats.Sum

Write-Host ''
Write-Host "Source  : $SourceFolder"                                           -ForegroundColor Cyan
Write-Host ('Content : {0:N0} files, {1:N2} GB' -f $stats.Count, ($totalBytes / 1GB)) -ForegroundColor Cyan
Write-Host "ISO     : $IsoPath"                                                -ForegroundColor Cyan
Write-Host "Label   : $VolumeName"                                             -ForegroundColor Cyan
if ($stats.Maximum -ge 4GB) {
    Write-Warning 'The folder contains files of 4 GB or more. ISO9660/Joliet cannot hold those; the file is only reachable via UDF, and IMAPI may refuse it.'
}

# ---------- Stream writer (IMAPI returns an IStream) ----------
if (-not ('IsoStreamWriter' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class IsoStreamWriter
{
    public static void Write(string path, object comStream, long totalBytes, bool overwrite, Action<long> progress)
    {
        IStream stream = (IStream)comStream;
        byte[] buffer  = new byte[4 * 1024 * 1024];
        IntPtr pRead   = Marshal.AllocHGlobal(sizeof(int));
        try
        {
            using (FileStream fs = new FileStream(path, overwrite ? FileMode.Create : FileMode.CreateNew,
                                                  FileAccess.Write, FileShare.None, 1024 * 1024))
            {
                long written = 0;
                long lastReport = 0;
                while (written < totalBytes)
                {
                    int want = (int)Math.Min(buffer.Length, totalBytes - written);
                    stream.Read(buffer, want, pRead);
                    int got = Marshal.ReadInt32(pRead);
                    if (got <= 0) break;
                    fs.Write(buffer, 0, got);
                    written += got;
                    if (progress != null && (written - lastReport >= 64L * 1024 * 1024 || written >= totalBytes))
                    {
                        progress(written);
                        lastReport = written;
                    }
                }
            }
        }
        finally
        {
            Marshal.FreeHGlobal(pRead);
        }
    }
}
'@
}

# ---------- Build image ----------
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
} catch {
    throw 'IMAPI2 (IMAPI2FS.MsftFileSystemImage) is not available on this system. It is included in desktop Windows and Server with Desktop Experience, but may be missing on Server Core.'
}

# Media type sets the capacity limit: BD-R (25 GB) if needed, otherwise DVD+R DL (8.5 GB)
$IMAPI_DVDPLUSR_DUALLAYER = 8
$IMAPI_BDR                = 18
$mediaType = if ($totalBytes -gt 8GB) { $IMAPI_BDR } else { $IMAPI_DVDPLUSR_DUALLAYER }
$fsi.ChooseImageDefaultsForMediaType($mediaType)
try { $fsi.FreeMediaBlocks = 0 } catch { }   # 0 = no capacity limit where supported

$fsi.FileSystemsToCreate = 7      # 1 = ISO9660, 2 = Joliet, 4 = UDF
$fsi.VolumeName          = $VolumeName

Write-Host ''
Write-Host 'Adding files to the image...' -ForegroundColor Yellow
try {
    $fsi.Root.AddTree($SourceFolder, [bool]$IncludeBaseFolder)
} catch {
    throw "Failed to add files: $($_.Exception.Message)`nCommon causes: total size exceeds the media limit, a file of 4 GB or more, or files that are locked or unreadable."
}

$result     = $fsi.CreateResultImage()
$imageBytes = [long]$result.BlockSize * [long]$result.TotalBlocks

Write-Host ('Writing ISO ({0:N2} GB)...' -f ($imageBytes / 1GB)) -ForegroundColor Yellow
$progress = [Action[long]] {
    param($done)
    $pct = if ($imageBytes -gt 0) { [int]([double]$done * 100 / [double]$imageBytes) } else { 100 }
    if ($pct -gt 100) { $pct = 100 }
    Write-Progress -Activity "Writing $IsoPath" -Status ('{0:N2} / {1:N2} GB' -f ($done / 1GB), ($imageBytes / 1GB)) -PercentComplete $pct
}

try {
    [IsoStreamWriter]::Write($IsoPath, $result.ImageStream, $imageBytes, [bool]$Force, $progress)
} catch {
    if (Test-Path -LiteralPath $IsoPath) { Remove-Item -LiteralPath $IsoPath -Force -ErrorAction SilentlyContinue }
    throw "Writing the ISO failed: $($_.Exception.Message)"
} finally {
    Write-Progress -Activity "Writing $IsoPath" -Completed
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($result)
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($fsi)
}
$sw.Stop()

$iso = Get-Item -LiteralPath $IsoPath
Write-Host ''
Write-Host ('ISO created: {0}  ({1:N2} GB, {2:N0} s)' -f $iso.FullName, ($iso.Length / 1GB), $sw.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host "Test it with: Mount-DiskImage -ImagePath '$($iso.FullName)'" -ForegroundColor DarkGray
