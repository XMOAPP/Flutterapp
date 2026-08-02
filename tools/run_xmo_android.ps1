param(
    [string]$Device = '0008634CS002555',
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
$shortPathRunner = Join-Path $PSScriptRoot 'flutter_short_path.ps1'
$flutterArguments = @(
    'run'
    '-d'
    $Device
    '--dart-define=XMO_HOMESERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com'
    '--dart-define=XMO_MATRIX_SERVER_NAME=xmo-matrix.centralindia.cloudapp.azure.com'
    '--dart-define=XMO_WALLET_AUTH_SERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/wallet'
    '--dart-define=XMO_STREAM_CHUNK_STORAGE=azure'
    '--dart-define=XMO_AZURE_CHUNK_SIGN_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/media/chunks/azure/sign-upload'
    '--dart-define=XMO_ACCOUNT_DELETION_SERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp'
    '--dart-define=XMO_ACCOUNT_DELETION_WEB_URL=https://xmo.dpdns.org/account-deletion'
    '--dart-define=XMO_INVITE_SERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp'
    '--dart-define=XMO_INVITE_WEB_BASE_URL=https://xmo.dpdns.org'
)

if ($Release) {
    $flutterArguments += '--release'
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File $shortPathRunner @flutterArguments
exit $LASTEXITCODE
