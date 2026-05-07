Add-Type -AssemblyName System.Drawing
$w = 1024
$bmp = New-Object System.Drawing.Bitmap $w, $w
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::FromArgb(255, 20, 107, 92))
$rectPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$r = 180
$rectPath.AddArc(0, 0, (2 * $r), (2 * $r), 180, 90)
$rectPath.AddArc(($w - 2 * $r), 0, (2 * $r), (2 * $r), 270, 90)
$rectPath.AddArc(($w - 2 * $r), ($w - 2 * $r), (2 * $r), (2 * $r), 0, 90)
$rectPath.AddArc(0, ($w - 2 * $r), (2 * $r), (2 * $r), 90, 90)
$rectPath.CloseFigure()
$brushGrad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
    (New-Object System.Drawing.Rectangle 0, 0, $w, $w),
    [System.Drawing.Color]::FromArgb(255, 26, 120, 100),
    [System.Drawing.Color]::FromArgb(255, 12, 90, 78),
    45.0
)
$g.FillPath($brushGrad, $rectPath)
$fontStyle = [System.Drawing.FontStyle]::Bold
$fontUnit = [System.Drawing.GraphicsUnit]::Pixel
$font = New-Object System.Drawing.Font "Segoe UI", 520, $fontStyle, $fontUnit
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center
$brushW = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$layout = New-Object System.Drawing.RectangleF 0, 40, $w, ($w - 40)
$g.DrawString("W", $font, $brushW, $layout, $sf)
$out = Join-Path $PSScriptRoot "..\assets\wordix_app_icon.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
Write-Host "Saved $out"
