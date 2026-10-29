[CmdletBinding()]
param(
    [ValidateSet("menu", "backup", "list", "restore", "enable-autostart", "disable-autostart", "settings")]
    [string]$Action = "menu"
)

# Zomboid Save Guard - automatic backups for Project Zomboid saves.
# ASCII only: Windows PowerShell 5.1 misreads UTF-8 without BOM.

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "config.json"
$LogPath    = Join-Path $ScriptDir "SaveGuard.log"

# ---------------------------------------------------------------- config ----

function Get-DefaultConfig {
    $zomboid = Join-Path $env:USERPROFILE "Zomboid"
    [pscustomobject]@{
        SavePath       = (Join-Path $zomboid "Saves")
        BackupPath     = (Join-Path $zomboid "backups\SaveGuard")
        KeepCount      = 10
        IncludeOptions = $true
    }
}

function Get-Config {
    if (-not (Test-Path $ConfigPath)) {
        $cfg = Get-DefaultConfig
        $cfg | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigPath -Encoding ascii
        Write-Host "Created default config: $ConfigPath" -ForegroundColor DarkGray
        return $cfg
    }
    Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

# ------------------------------------------------------------------ log -----

function Write-Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $LogPath -Value $line -Encoding ascii -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------- helpers ----

function Format-Size([long]$Bytes) {
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    return "{0:N0} KB" -f ($Bytes / 1KB)
}

function Test-GameRunning {
    $procs = Get-Process -Name "ProjectZomboid64", "ProjectZomboid32", "ProjectZomboid" -ErrorAction SilentlyContinue
    return [bool]$procs
}

function Get-BackupList($Config) {
    if (-not (Test-Path $Config.BackupPath)) { return @() }
    @(Get-ChildItem -Path $Config.BackupPath -Filter "saves_*.zip" -File |
        Sort-Object LastWriteTime -Descending)
}

# ---------------------------------------------------------------- backup ----

function Invoke-Backup {
    $cfg = Get-Config

    if (-not (Test-Path $cfg.SavePath)) {
        throw "Save folder not found: $($cfg.SavePath). Edit $ConfigPath"
    }
    if (-not (Test-Path $cfg.BackupPath)) {
        New-Item -ItemType Directory -Path $cfg.BackupPath -Force | Out-Null
    }

    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $zip   = Join-Path $cfg.BackupPath "saves_$stamp.zip"
    $root  = Split-Path -Parent $cfg.SavePath

    $items = @($cfg.SavePath)
    if ($cfg.IncludeOptions) {
        foreach ($name in @("options.ini", "latestSave.ini")) {
            $file = Join-Path $root $name
            if (Test-Path $file) { $items += $file }
        }
    }

    Write-Host "Archiving $($cfg.SavePath) ..." -ForegroundColor DarkGray
    Compress-Archive -Path $items -DestinationPath $zip -CompressionLevel Optimal -Force

    $size = Format-Size (Get-Item $zip).Length
    Write-Host "Backup created: $(Split-Path -Leaf $zip) ($size)" -ForegroundColor Green
    Write-Log "backup $zip ($size)"

    $all = Get-BackupList $cfg
    if ($all.Count -gt $cfg.KeepCount) {
        $old = $all | Select-Object -Skip $cfg.KeepCount
        foreach ($f in $old) {
            Remove-Item $f.FullName -Force
            Write-Host "Pruned old backup: $($f.Name)" -ForegroundColor DarkGray
            Write-Log "pruned $($f.Name)"
        }
    }
}

# ------------------------------------------------------------------ list ----

function Show-Backups {
    $cfg = Get-Config
    $list = Get-BackupList $cfg
    if ($list.Count -eq 0) {
        Write-Host "No backups yet in $($cfg.BackupPath)" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host ("{0,3}  {1,-24}  {2,10}  {3}" -f "#", "Created", "Size", "File") -ForegroundColor Cyan
    Write-Host ("{0,3}  {1,-24}  {2,10}  {3}" -f "-", "-------", "----", "----")
    for ($i = 0; $i -lt $list.Count; $i++) {
        $b = $list[$i]
        Write-Host ("{0,3}  {1,-24}  {2,10}  {3}" -f ($i + 1), $b.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), (Format-Size $b.Length), $b.Name)
    }
    Write-Host ""
    Write-Host "Folder: $($cfg.BackupPath)" -ForegroundColor DarkGray
}

# --------------------------------------------------------------- restore ----

function Invoke-Restore {
    $cfg  = Get-Config
    $list = Get-BackupList $cfg
    if ($list.Count -eq 0) {
        Write-Host "No backups to restore." -ForegroundColor Yellow
        return
    }

    Show-Backups
    $answer = Read-Host "Enter number to restore (empty to cancel)"
    if ([string]::IsNullOrWhiteSpace($answer)) { return }

    $index = 0
    if (-not [int]::TryParse($answer, [ref]$index) -or $index -lt 1 -or $index -gt $list.Count) {
        Write-Host "Invalid number." -ForegroundColor Red
        return
    }
    $zip = $list[$index - 1]

    if (Test-GameRunning) {
        Write-Host "Close Project Zomboid before restoring." -ForegroundColor Red
        return
    }

    $confirm = Read-Host "Restore '$($zip.Name)'? Current saves will be moved aside (y/N)"
    if ($confirm -ne "y") { return }

    $root  = Split-Path -Parent $cfg.SavePath
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $tmp   = Join-Path $env:TEMP ("SaveGuard_" + [guid]::NewGuid().ToString("N"))

    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        Expand-Archive -Path $zip.FullName -DestinationPath $tmp -Force

        $extracted = Join-Path $tmp "Saves"
        if (-not (Test-Path $extracted)) {
            throw "Archive does not contain a Saves folder: $($zip.Name)"
        }

        if (Test-Path $cfg.SavePath) {
            $aside = Join-Path $root "Saves.before-restore-$stamp"
            Move-Item -Path $cfg.SavePath -Destination $aside
            Write-Host "Current saves moved to: $aside" -ForegroundColor DarkGray
        }

        Copy-Item -Path $extracted -Destination $cfg.SavePath -Recurse -Force

        foreach ($name in @("options.ini", "latestSave.ini")) {
            $src = Join-Path $tmp $name
            if (Test-Path $src) {
                $dst = Join-Path $root $name
                if (Test-Path $dst) { Copy-Item $dst "$dst.before-restore-$stamp" -Force }
                Copy-Item $src $dst -Force
            }
        }

        Write-Host "Restored: $($zip.Name)" -ForegroundColor Green
        Write-Log "restore $($zip.FullName)"
    }
    finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------- autostart ----

function Get-StartupFolder {
    [Environment]::GetFolderPath("Startup")
}

function Get-ShortcutPath {
    Join-Path (Get-StartupFolder) "Zomboid Save Guard.lnk"
}

function Test-Autostart {
    Test-Path (Get-ShortcutPath)
}

function Enable-Autostart {
    $script = Join-Path $ScriptDir "SaveGuard.ps1"
    $lnk    = Get-ShortcutPath

    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnk)
    $shortcut.TargetPath       = "powershell.exe"
    $shortcut.Arguments        = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`" -Action backup"
    $shortcut.WorkingDirectory = $ScriptDir
    $shortcut.WindowStyle      = 7
    $shortcut.Description      = "Backup Project Zomboid saves at logon"
    $shortcut.Save()

    Write-Host "Autostart enabled: $lnk" -ForegroundColor Green
    Write-Host "A backup will run silently every time you log in." -ForegroundColor DarkGray
    Write-Log "autostart enabled"
}

function Disable-Autostart {
    $lnk = Get-ShortcutPath
    if (-not (Test-Path $lnk)) {
        Write-Host "Autostart is not enabled." -ForegroundColor Yellow
        return
    }
    Remove-Item $lnk -Force
    Write-Host "Autostart disabled." -ForegroundColor Green
    Write-Log "autostart disabled"
}

# ------------------------------------------------------------------ menu ----

function Show-Menu {
    $cfg = Get-Config
    $list = Get-BackupList $cfg
    $auto = Test-Autostart

    Clear-Host
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "        Zomboid Save Guard" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "Saves:    $($cfg.SavePath)"
    Write-Host "Backups:  $($cfg.BackupPath)"
    Write-Host "Stored:   $($list.Count) of $($cfg.KeepCount)"
    Write-Host "Autostart: $(if ($auto) { 'enabled' } else { 'disabled' })"
    Write-Host ""
    Write-Host "  1) Backup now"
    Write-Host "  2) List backups"
    Write-Host "  3) Restore backup"
    Write-Host "  4) Enable autostart (every logon)"
    Write-Host "  5) Disable autostart"
    Write-Host "  6) Open settings"
    Write-Host "  7) Open backup folder"
    Write-Host "  0) Exit"
    Write-Host ""
}

function Start-Menu {
    while ($true) {
        Show-Menu
        $choice = Read-Host "Select"
        switch ($choice) {
            "1" { try { Invoke-Backup } catch { Write-Host "ERROR: $_" -ForegroundColor Red }; Read-Host "Press Enter" }
            "2" { Show-Backups; Read-Host "Press Enter" }
            "3" { try { Invoke-Restore } catch { Write-Host "ERROR: $_" -ForegroundColor Red }; Read-Host "Press Enter" }
            "4" { try { Enable-Autostart } catch { Write-Host "ERROR: $_" -ForegroundColor Red }; Read-Host "Press Enter" }
            "5" { try { Disable-Autostart } catch { Write-Host "ERROR: $_" -ForegroundColor Red }; Read-Host "Press Enter" }
            "6" { $null = Get-Config; Start-Process notepad.exe $ConfigPath }
            "7" { $c = Get-Config; if (Test-Path $c.BackupPath) { Start-Process explorer.exe $c.BackupPath } }
            "0" { return }
            default { }
        }
    }
}

# ------------------------------------------------------------------ main ----

switch ($Action) {
    "backup"            { Invoke-Backup }
    "list"              { Show-Backups }
    "restore"           { Invoke-Restore }
    "enable-autostart"  { Enable-Autostart }
    "disable-autostart" { Disable-Autostart }
    "settings"          { $null = Get-Config; Start-Process notepad.exe $ConfigPath }
    "menu"              { Start-Menu }
}
