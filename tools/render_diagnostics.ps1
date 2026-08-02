param(
    [string]$InputPath = "build\vodozemac_build.txt",
    [string]$OutputPath = "build\vodozemac_diagnostics.png"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$sourceLines = Get-Content -LiteralPath $InputPath
$diagnosticLines = @(
    $sourceLines |
        Where-Object {
            $_ -match "Error:" -or
            $_ -match "error -" -or
            $_ -match "warning -" -or
            $_ -match "lib[\\/].+:\d+:\d+"
        } |
        Select-Object -First 120
)

if ($diagnosticLines.Count -eq 0) {
    $diagnosticLines = @($sourceLines | Select-Object -Last 100)
}

$wrappedLines = [System.Collections.Generic.List[string]]::new()
foreach ($line in $diagnosticLines) {
    $remaining = [string]$line
    if ($remaining.Length -eq 0) {
        $wrappedLines.Add("")
        continue
    }

    while ($remaining.Length -gt 150) {
        $wrappedLines.Add($remaining.Substring(0, 150))
        $remaining = "  " + $remaining.Substring(150)
    }
    $wrappedLines.Add($remaining)
}

$font = [System.Drawing.Font]::new("Consolas", 13)
$lineHeight = [Math]::Ceiling($font.GetHeight()) + 3
$width = 2100
$height = [Math]::Max(240, ($wrappedLines.Count + 2) * $lineHeight)
$bitmap = [System.Drawing.Bitmap]::new($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::FromArgb(18, 18, 18))
$brush = [System.Drawing.Brushes]::White

try {
    $y = 16
    foreach ($line in $wrappedLines) {
        $graphics.DrawString($line, $font, $brush, 16, $y)
        $y += $lineHeight
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory) {
        New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    }
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    $font.Dispose()
}
