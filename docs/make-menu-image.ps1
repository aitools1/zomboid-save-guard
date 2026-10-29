Add-Type -AssemblyName System.Drawing

$w = 900
$h = 580
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

$bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(10, 12, 16))
$g.FillRectangle($bg, 0, 0, $w, $h)

$font  = New-Object System.Drawing.Font("Consolas", 15)
$bold  = New-Object System.Drawing.Font("Consolas", 15, [System.Drawing.FontStyle]::Bold)
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(225, 228, 232))
$cyan  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(80, 200, 255))
$gray  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(130, 138, 150))
$green = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(90, 210, 130))

$lines = @(
    @{ t = "PS C:\ZomboidSaveGuard> .\SaveGuard.ps1"; c = $gray; f = $font },
    @{ t = ""; c = $white; f = $font },
    @{ t = "======================================"; c = $cyan; f = $font },
    @{ t = "        Zomboid Save Guard"; c = $cyan; f = $bold },
    @{ t = "======================================"; c = $cyan; f = $font },
    @{ t = "Saves:     C:\Users\vetmo\Zomboid\Saves"; c = $white; f = $font },
    @{ t = "Backups:   C:\Users\vetmo\Zomboid\backups\SaveGuard"; c = $white; f = $font },
    @{ t = "Stored:    3 of 10"; c = $white; f = $font },
    @{ t = "Autostart: enabled"; c = $green; f = $font },
    @{ t = ""; c = $white; f = $font },
    @{ t = "  1) Backup now"; c = $white; f = $font },
    @{ t = "  2) List backups"; c = $white; f = $font },
    @{ t = "  3) Restore backup"; c = $white; f = $font },
    @{ t = "  4) Enable autostart (every logon)"; c = $white; f = $font },
    @{ t = "  5) Disable autostart"; c = $white; f = $font },
    @{ t = "  6) Open settings"; c = $white; f = $font },
    @{ t = "  7) Open backup folder"; c = $white; f = $font },
    @{ t = "  0) Exit"; c = $white; f = $font },
    @{ t = ""; c = $white; f = $font },
    @{ t = "Select: 1"; c = $white; f = $font },
    @{ t = "Archiving C:\Users\vetmo\Zomboid\Saves ..."; c = $gray; f = $font },
    @{ t = "Backup created: saves_2026-10-29_01-36-46.zip (68.6 MB)"; c = $green; f = $font }
)

$y = 26
foreach ($line in $lines) {
    if ($line.t -ne "") {
        $g.DrawString($line.t, $line.f, $line.c, 26, $y)
    }
    $y += 24
}

$out = Join-Path $PSScriptRoot "menu.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
Write-Host "Saved: $out"
