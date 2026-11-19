<#
.SYNOPSIS
    Lists the largest folders on a drive (largest first, sizes in GB) and lets you
    drill down into any folder to see what's using the space beneath it.

.DESCRIPTION
    - Scans the drive (or -Path) once and keeps the size of EVERY folder in memory,
      so drilling down and going back up is instant, with no rescans
    - Shows the top N subfolders of the current folder, plus the files lying directly in it
    - Navigate: number = open that folder, U = up one level, R = back to the start, Q = quit
    - Skips junctions/symlinks (e.g. "Documents and Settings") so nothing is counted twice
    - Includes hidden and system folders/files
    - Folders that can't be read are skipped and counted. Run as Administrator for complete
      numbers (Windows, ProgramData, other users' profiles)

.EXAMPLE
    .\Get-TopFolders.ps1
    # lists the drives, asks for a letter, scans, then lets you drill down

.EXAMPLE
    .\Get-TopFolders.ps1 -DriveLetter C -Top 15

.EXAMPLE
    .\Get-TopFolders.ps1 -Path C:\Windows

.EXAMPLE
    .\Get-TopFolders.ps1 -DriveLetter D -NoDrillDown -ExportCsv C:\Temp\d-folders.csv
#>
[CmdletBinding(DefaultParameterSetName = 'Drive')]
param(
    [Parameter(ParameterSetName = 'Drive')]
    [ValidatePattern('^[A-Za-z]:?$')]
    [string] $DriveLetter,

    [Parameter(ParameterSetName = 'Path')]
    [string] $Path,

    [ValidateRange(1, 1000)]
    [int] $Top = 10,

    [switch] $NoDrillDown,      # only show the first list, no interactive navigation

    [string] $ExportCsv         # export every scanned folder (path, depth, size, files)
)

$ErrorActionPreference = 'Stop'

# ---------- Resolve target ----------
if ($PSCmdlet.ParameterSetName -eq 'Path' -and $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Folder not found: $Path" }
    $root = (Resolve-Path -LiteralPath $Path).Path
    if ($root -notmatch '^[A-Za-z]:\\$') { $root = $root.TrimEnd('\') }
} else {
    if (-not $DriveLetter) {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -and ($_.Used + $_.Free) -gt 0 }
        Write-Host 'Available drives:' -ForegroundColor Cyan
        foreach ($d in $drives) {
            Write-Host ('  {0}:  {1,8:N1} GB used / {2,8:N1} GB free' -f $d.Name, ($d.Used / 1GB), ($d.Free / 1GB))
        }
        do { $DriveLetter = Read-Host 'Drive letter' } until ($DriveLetter -match '^[A-Za-z]:?$')
    }
    $root = $DriveLetter.Substring(0, 1).ToUpper() + ':\'
    if (-not (Test-Path -LiteralPath $root)) { throw "Drive $root not found." }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
               [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning 'Not running as Administrator. Some folders (e.g. Windows, ProgramData, other user profiles) may be partly unreadable and show too small.'
}

# ---------- Scanner (C# for speed; keeps the whole folder tree with sizes) ----------
if (-not ('TopFolders.DirTree' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;

namespace TopFolders
{
    public class DirNode
    {
        public string Path;
        public string Name;
        public int    Parent;
        public int    Depth;
        public long   OwnBytes;
        public long   OwnFiles;
        public long   TotalBytes;
        public long   TotalFiles;
        public bool   Denied;
        public List<int> Children = new List<int>();
    }

    public class DirTree
    {
        public List<DirNode> Nodes = new List<DirNode>();
        public int DeniedCount;

        public DirTree(string rootPath)
        {
            DirNode root = new DirNode();
            root.Path = rootPath; root.Name = rootPath; root.Parent = -1; root.Depth = 0;
            Nodes.Add(root);
            ScanFiles(root, new DirectoryInfo(rootPath));
        }

        private void ScanFiles(DirNode node, DirectoryInfo dir)
        {
            try
            {
                foreach (FileInfo f in dir.EnumerateFiles())
                {
                    node.OwnBytes += f.Length;
                    node.OwnFiles++;
                }
            }
            catch { if (!node.Denied) { node.Denied = true; DeniedCount++; } }
        }

        // Scans one folder (and everything below it) and attaches it to the root
        public void AddTopLevel(DirectoryInfo dir)
        {
            int start = Nodes.Count;
            Stack<KeyValuePair<DirectoryInfo, int>> stack = new Stack<KeyValuePair<DirectoryInfo, int>>();
            stack.Push(new KeyValuePair<DirectoryInfo, int>(dir, 0));

            while (stack.Count > 0)
            {
                KeyValuePair<DirectoryInfo, int> item = stack.Pop();
                DirectoryInfo d = item.Key;
                int idx = Nodes.Count;

                DirNode n = new DirNode();
                n.Path   = d.FullName;
                n.Name   = d.Name;
                n.Parent = item.Value;
                n.Depth  = Nodes[item.Value].Depth + 1;
                Nodes.Add(n);
                Nodes[item.Value].Children.Add(idx);

                ScanFiles(n, d);
                try
                {
                    foreach (DirectoryInfo s in d.EnumerateDirectories())
                    {
                        if ((s.Attributes & FileAttributes.ReparsePoint) == 0)
                            stack.Push(new KeyValuePair<DirectoryInfo, int>(s, idx));
                    }
                }
                catch { if (!n.Denied) { n.Denied = true; DeniedCount++; } }
            }

            // Children always have a higher index than their parent: sum up bottom-up
            for (int i = Nodes.Count - 1; i >= start; i--)
            {
                DirNode n = Nodes[i];
                n.TotalBytes += n.OwnBytes;
                n.TotalFiles += n.OwnFiles;
                if (i > start)
                {
                    Nodes[n.Parent].TotalBytes += n.TotalBytes;
                    Nodes[n.Parent].TotalFiles += n.TotalFiles;
                }
            }
        }

        public void FinalizeRoot()
        {
            DirNode root = Nodes[0];
            root.TotalBytes = root.OwnBytes;
            root.TotalFiles = root.OwnFiles;
            foreach (int c in root.Children)
            {
                root.TotalBytes += Nodes[c].TotalBytes;
                root.TotalFiles += Nodes[c].TotalFiles;
            }
        }

        // Number of unreadable folders at or below a node
        public int DeniedBelow(int index)
        {
            int count = 0;
            Stack<int> st = new Stack<int>();
            st.Push(index);
            while (st.Count > 0)
            {
                int i = st.Pop();
                if (Nodes[i].Denied) count++;
                foreach (int c in Nodes[i].Children) st.Push(c);
            }
            return count;
        }
    }
}
'@
}

# ---------- Scan ----------
Write-Host "Scanning $root ..." -ForegroundColor Yellow
$sw   = [Diagnostics.Stopwatch]::StartNew()
$tree = New-Object TopFolders.DirTree $root

$rootInfo = New-Object IO.DirectoryInfo $root
try {
    $topDirs = @($rootInfo.EnumerateDirectories() |
                 Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
} catch {
    throw "Cannot list $root : $($_.Exception.Message)"
}
for ($i = 0; $i -lt $topDirs.Count; $i++) {
    Write-Progress -Activity "Scanning $root" -Status "$($topDirs[$i].Name)  ($($i + 1)/$($topDirs.Count))" `
                   -PercentComplete ([int](100 * $i / [Math]::Max(1, $topDirs.Count)))
    $tree.AddTopLevel($topDirs[$i])
}
$tree.FinalizeRoot()
Write-Progress -Activity "Scanning $root" -Completed
$sw.Stop()

$rootNode = $tree.Nodes[0]
Write-Host ('Scanned {0:N0} folders, {1:N2} GB in {2:N0} s' -f ($tree.Nodes.Count - 1), ($rootNode.TotalBytes / 1GB), $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray

if ($PSCmdlet.ParameterSetName -ne 'Path') {
    $drv = Get-PSDrive -Name $root.Substring(0, 1)
    if ($drv.Used -ne $null) {
        Write-Host ('Drive {0}  used {1:N2} GB, free {2:N2} GB' -f $root, ($drv.Used / 1GB), ($drv.Free / 1GB)) -ForegroundColor DarkGray
        $gap = ($drv.Used - $rootNode.TotalBytes) / 1GB
        if ($gap -gt 1) {
            Write-Host ('{0:N2} GB of used space was not counted (e.g. pagefile/hiberfil, System Volume Information, shadow copies, unreadable folders).' -f $gap) -ForegroundColor DarkGray
        }
    }
}
if ($tree.DeniedCount -gt 0) {
    Write-Warning "$($tree.DeniedCount) folder(s) could not be read and were skipped$(if (-not $isAdmin) { ' (run as Administrator)' })."
}

# ---------- Export ----------
if ($ExportCsv) {
    $tree.Nodes | Select-Object Path, Depth,
                    @{ n = 'SizeGB'; e = { [Math]::Round($_.TotalBytes / 1GB, 3) } },
                    @{ n = 'Files';  e = { $_.TotalFiles } },
                    @{ n = 'Bytes';  e = { $_.TotalBytes } } |
        Sort-Object Bytes -Descending |
        Export-Csv -LiteralPath $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "All $($tree.Nodes.Count) folders exported to $ExportCsv" -ForegroundColor Green
}

# ---------- Display ----------
function Show-Level([int]$Index) {
    $node = $tree.Nodes[$Index]
    $kids = @($node.Children | ForEach-Object { $tree.Nodes[$_] } | Sort-Object TotalBytes -Descending | Select-Object -First $Top)

    Write-Host ''
    Write-Host ('{0}   ({1:N2} GB, {2:N0} files)' -f $node.Path, ($node.TotalBytes / 1GB), $node.TotalFiles) -ForegroundColor Cyan
    if ($node.Children.Count -eq 0) {
        Write-Host '  (no subfolders)' -ForegroundColor DarkGray
    } else {
        Write-Host ("  Top {0} of {1} subfolders" -f $kids.Count, $node.Children.Count) -ForegroundColor DarkGray
    }

    $rows = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $kids.Count; $i++) {
        $k   = $kids[$i]
        $pct = if ($node.TotalBytes -gt 0) { [double]$k.TotalBytes * 100 / [double]$node.TotalBytes } else { 0 }
        $flag = if ($tree.DeniedBelow($indexOf[$k.Path]) -gt 0) { '*' } else { '' }
        $rows.Add([pscustomobject]@{
            '#'         = $i + 1
            'Folder'    = $k.Name + $flag
            'Size (GB)' = '{0:N2}' -f ($k.TotalBytes / 1GB)
            '%'         = '{0:N1}' -f $pct
            'Files'     = '{0:N0}' -f $k.TotalFiles
            'Subdirs'   = $k.Children.Count
        })
    }
    if ($node.OwnFiles -gt 0) {
        $pct = if ($node.TotalBytes -gt 0) { [double]$node.OwnBytes * 100 / [double]$node.TotalBytes } else { 0 }
        $rows.Add([pscustomobject]@{
            '#'         = '-'
            'Folder'    = '[files in this folder]'
            'Size (GB)' = '{0:N2}' -f ($node.OwnBytes / 1GB)
            '%'         = '{0:N1}' -f $pct
            'Files'     = '{0:N0}' -f $node.OwnFiles
            'Subdirs'   = ''
        })
    }
    if ($rows.Count -gt 0) { $rows | Format-Table -AutoSize | Out-String -Width 4096 | Write-Host }
    if ($rows | Where-Object { $_.Folder -like '*`*' }) {
        Write-Host '  * = contains folders that could not be read (size may be higher)' -ForegroundColor DarkGray
    }
    return , $kids
}

# Index lookup for nodes (IndexOf on a large list is slow)
$indexOf = @{}
for ($i = 0; $i -lt $tree.Nodes.Count; $i++) { $indexOf[$tree.Nodes[$i].Path] = $i }

$current = 0
$kids = Show-Level $current
if ($NoDrillDown) { return }

while ($true) {
    $prompt = if ($kids.Count -gt 0) { "Open folder [1-$($kids.Count)], U = up, R = start, Q = quit" } else { 'U = up, R = start, Q = quit' }
    $in   = (Read-Host $prompt).Trim()
    $next = $null
    if     ($in -match '^[Qq]$') { return }
    elseif ($in -match '^[Uu]$') {
        if ($tree.Nodes[$current].Parent -ge 0) { $next = $tree.Nodes[$current].Parent }
        else { Write-Host '  Already at the top.' -ForegroundColor Yellow }
    }
    elseif ($in -match '^[Rr]$') { $next = 0 }
    elseif ($in -match '^\d+$') {
        $n = [int]$in
        if ($n -ge 1 -and $n -le $kids.Count) { $next = $indexOf[$kids[$n - 1].Path] }
        else { Write-Host "  Enter a number between 1 and $($kids.Count)." -ForegroundColor Yellow }
    }
    else { Write-Host '  Unknown choice.' -ForegroundColor Yellow }

    if ($null -ne $next) {
        $current = $next
        $kids = Show-Level $current
    }
}
