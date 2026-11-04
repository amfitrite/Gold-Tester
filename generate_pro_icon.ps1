Add-Type -AssemblyName System.Drawing

$assetsDir = 'd:\CSV\dukascopy-downloader\assets'
if (!(Test-Path $assetsDir)) {
    New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null
}

function Create-AppIconImage([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $scale = $size / 256.0

    # 1. Base Squircle / Rounded Badge Background
    $rect = New-Object System.Drawing.RectangleF (10 * $scale), (10 * $scale), (236 * $scale), (236 * $scale)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $radius = 48.0 * $scale
    $dia = $radius * 2

    $path.AddArc($rect.X, $rect.Y, $dia, $dia, 180, 90)
    $path.AddArc($rect.Right - $dia, $rect.Y, $dia, $dia, 270, 90)
    $path.AddArc($rect.Right - $dia, $rect.Bottom - $dia, $dia, $dia, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $dia, $dia, $dia, 90, 90)
    $path.CloseFigure()

    # Dark Obsidian Gradient Fill
    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF 0, 0),
        (New-Object System.Drawing.PointF ($size), ($size)),
        ([System.Drawing.Color]::FromArgb(255, 13, 20, 36)),
        ([System.Drawing.Color]::FromArgb(255, 4, 7, 14))
    )
    $g.FillPath($bgBrush, $path)
    $bgBrush.Dispose()

    # Gold Metallic Outer Border with Glow
    $goldPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 245, 158, 11), (7.0 * $scale))
    $goldPen.Alignment = [System.Drawing.Drawing2D.PenAlignment]::Center
    $g.DrawPath($goldPen, $path)
    $goldPen.Dispose()

    # Inner subtle glow border
    $innerGlow = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120, 56, 189, 248), (2.0 * $scale))
    $rectInner = New-Object System.Drawing.RectangleF (16 * $scale), (16 * $scale), (224 * $scale), (224 * $scale)
    $pathInner = New-Object System.Drawing.Drawing2D.GraphicsPath
    $radInner = 42.0 * $scale
    $diaInner = $radInner * 2
    $pathInner.AddArc($rectInner.X, $rectInner.Y, $diaInner, $diaInner, 180, 90)
    $pathInner.AddArc($rectInner.Right - $diaInner, $rectInner.Y, $diaInner, $diaInner, 270, 90)
    $pathInner.AddArc($rectInner.Right - $diaInner, $rectInner.Bottom - $diaInner, $diaInner, $diaInner, 0, 90)
    $pathInner.AddArc($rectInner.X, $rectInner.Bottom - $diaInner, $diaInner, $diaInner, 90, 90)
    $pathInner.CloseFigure()
    $g.DrawPath($innerGlow, $pathInner)
    $innerGlow.Dispose()
    $pathInner.Dispose()

    # 2. Bullish Candlestick (Emerald Green with Gradient)
    $wickPenGreen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 16, 185, 129), (4.0 * $scale))
    $g.DrawLine($wickPenGreen, (65 * $scale), (40 * $scale), (65 * $scale), (185 * $scale))
    $wickPenGreen.Dispose()

    $rectGreen = New-Object System.Drawing.RectangleF (50 * $scale), (75 * $scale), (30 * $scale), (80 * $scale)
    $greenBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rectGreen,
        ([System.Drawing.Color]::FromArgb(255, 52, 211, 153)),
        ([System.Drawing.Color]::FromArgb(255, 5, 150, 105)),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $g.FillRectangle($greenBrush, $rectGreen)
    $greenBrush.Dispose()

    # 3. Gold Master Candlestick (XAUUSD Gold Bullion)
    $wickPenGold = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 251, 191, 36), (4.5 * $scale))
    $g.DrawLine($wickPenGold, (128 * $scale), (25 * $scale), (128 * $scale), (185 * $scale))
    $wickPenGold.Dispose()

    $rectGold = New-Object System.Drawing.RectangleF (112 * $scale), (50 * $scale), (32 * $scale), (105 * $scale)
    $goldBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rectGold,
        ([System.Drawing.Color]::FromArgb(255, 253, 230, 138)),
        ([System.Drawing.Color]::FromArgb(255, 217, 119, 6)),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $g.FillRectangle($goldBrush, $rectGold)
    $goldBrush.Dispose()

    # Highlight line on gold bar
    $goldHlPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 255, 255, 255), (1.5 * $scale))
    $g.DrawLine($goldHlPen, (116 * $scale), (54 * $scale), (116 * $scale), (150 * $scale))
    $goldHlPen.Dispose()

    # 4. Liquidity Sweep Curve (Cyan Neon Arc sweeping the high)
    $sweepPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 56, 189, 248), (4.0 * $scale))
    $sweepPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $sweepPen.EndCap = [System.Drawing.Drawing2D.LineCap]::ArrowAnchor
    $g.DrawArc($sweepPen, (35 * $scale), (22 * $scale), (170 * $scale), (60 * $scale), 200, 140)
    $sweepPen.Dispose()

    # Sweep Level Dotted Line
    $dashPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180, 239, 68, 68), (2.0 * $scale))
    $dashPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $g.DrawLine($dashPen, (40 * $scale), (50 * $scale), (210 * $scale), (50 * $scale))
    $dashPen.Dispose()

    # 5. Download Badge (Bottom Right Circle)
    $badgeRect = New-Object System.Drawing.RectangleF (145 * $scale), (145 * $scale), (82 * $scale), (82 * $scale)
    $badgeBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $badgeRect,
        ([System.Drawing.Color]::FromArgb(255, 14, 165, 233)),
        ([System.Drawing.Color]::FromArgb(255, 2, 132, 199)),
        [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal
    )
    $g.FillEllipse($badgeBrush, $badgeRect)
    $badgeBrush.Dispose()

    $badgeBorder = New-Object System.Drawing.Pen([System.Drawing.Color]::White, (2.5 * $scale))
    $g.DrawEllipse($badgeBorder, $badgeRect)
    $badgeBorder.Dispose()

    # White Arrow inside Download Badge
    $whitePen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, (6.0 * $scale))
    $whitePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $whitePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    # Arrow shaft
    $g.DrawLine($whitePen, (186 * $scale), (160 * $scale), (186 * $scale), (198 * $scale))
    # Arrow head
    $g.DrawLine($whitePen, (172 * $scale), (186 * $scale), (186 * $scale), (200 * $scale))
    $g.DrawLine($whitePen, (200 * $scale), (186 * $scale), (186 * $scale), (200 * $scale))
    # Tray
    $g.DrawLine($whitePen, (168 * $scale), (212 * $scale), (204 * $scale), (212 * $scale))
    $whitePen.Dispose()

    $path.Dispose()
    $g.Dispose()

    return $bmp
}

Write-Host "Creating multi-resolution icon..."
$bmp256 = Create-AppIconImage 256
$pngPath = Join-Path $assetsDir 'icon.png'
$bmp256.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)

# Generate multi-size ICO: 256, 128, 64, 48, 32, 16
$sizes = @(256, 128, 64, 48, 32, 16)
$images = @()
foreach ($s in $sizes) {
    if ($s -eq 256) {
        $images += $bmp256
    } else {
        $images += Create-AppIconImage $s
    }
}

# Write multi-frame ICO binary stream
$icoPath = Join-Path $assetsDir 'icon.ico'
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $ms

# ICONDIR header
$bw.Write([UInt16]0) # Reserved
$bw.Write([UInt16]1) # Type (1 = ICO)
$bw.Write([UInt16]$images.Count) # Number of images

$pngBytesList = @()
foreach ($img in $images) {
    $tempMs = New-Object System.IO.MemoryStream
    $img.Save($tempMs, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBytesList += ,$tempMs.ToArray()
    $tempMs.Dispose()
}

$offset = 6 + (16 * $images.Count)
for ($i = 0; $i -lt $images.Count; $i++) {
    $sz = $sizes[$i]
    $wByte = if ($sz -ge 256) { [byte]0 } else { [byte]$sz }
    $hByte = if ($sz -ge 256) { [byte]0 } else { [byte]$sz }
    $dataLen = $pngBytesList[$i].Length

    # ICONDIRENTRY
    $bw.Write($wByte)            # Width
    $bw.Write($hByte)            # Height
    $bw.Write([byte]0)           # Color count
    $bw.Write([byte]0)           # Reserved
    $bw.Write([UInt16]1)         # Color planes
    $bw.Write([UInt16]32)        # Bits per pixel
    $bw.Write([UInt32]$dataLen)  # Image bytes size
    $bw.Write([UInt32]$offset)   # Image offset

    $offset += $dataLen
}

# Write PNG data for each icon entry
for ($i = 0; $i -lt $images.Count; $i++) {
    $bw.Write($pngBytesList[$i])
}

$bw.Flush()
[System.IO.File]::WriteAllBytes($icoPath, $ms.ToArray())
$bw.Dispose()
$ms.Dispose()

foreach ($img in $images) {
    $img.Dispose()
}

Write-Host "Multi-resolution icon saved to: $icoPath"
