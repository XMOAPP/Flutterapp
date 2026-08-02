[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PlaySigningSha256,

    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'

$fingerprint = $PlaySigningSha256.Trim().ToUpperInvariant()
if ($fingerprint -notmatch '^(?:[0-9A-F]{2}:){31}[0-9A-F]{2}$') {
    throw 'PlaySigningSha256 must be the colon-separated SHA-256 fingerprint from Google Play App Signing.'
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceDirectory = Join-Path $projectRoot 'deploy\netlify-invite'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'build\netlify-invite'
}

$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
$wellKnownPath = Join-Path $outputPath '.well-known'
$joinPath = Join-Path $outputPath 'join'

New-Item -ItemType Directory -Path $wellKnownPath -Force | Out-Null
New-Item -ItemType Directory -Path $joinPath -Force | Out-Null

Copy-Item (Join-Path $sourceDirectory '_headers') $outputPath -Force
Copy-Item (Join-Path $sourceDirectory '_redirects') $outputPath -Force
Copy-Item (Join-Path $sourceDirectory 'join\index.html') $joinPath -Force

$templatePath = Join-Path $sourceDirectory '.well-known\assetlinks.json.template'
$assetLinks = [IO.File]::ReadAllText($templatePath).Replace(
    'REPLACE_WITH_GOOGLE_PLAY_APP_SIGNING_SHA256',
    $fingerprint
)

if ($assetLinks.Contains('REPLACE_WITH_GOOGLE_PLAY_APP_SIGNING_SHA256')) {
    throw 'The assetlinks.json signing fingerprint placeholder was not replaced.'
}

$parsedAssetLinks = $assetLinks | ConvertFrom-Json
if ($parsedAssetLinks.Count -ne 1 -or
    $parsedAssetLinks[0].target.package_name -ne 'com.xmo.xmo') {
    throw 'The generated assetlinks.json does not target com.xmo.xmo.'
}

$assetLinksPath = Join-Path $wellKnownPath 'assetlinks.json'
$utf8WithoutBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($assetLinksPath, $assetLinks, $utf8WithoutBom)

Write-Host "Netlify invite bundle prepared at: $outputPath"
Write-Host 'Deploy these files into the root of the existing xmo.dpdns.org Netlify site.'
Write-Host 'Verify: https://xmo.dpdns.org/.well-known/assetlinks.json'
Write-Host 'Verify: https://xmo.dpdns.org/join/invalid-token'
