param(
    [string]$HostName = "xmo-matrix.centralindia.cloudapp.azure.com",
    [string]$UserName = "azureuser",
    [string]$KeyPath = "$env:USERPROFILE\Downloads\xmo-matrix-key.pem",
    [string]$RemoteDirectory = "/opt/xmo",
    [string]$OutputDirectory = "build/deployment_snapshots"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $KeyPath)) {
    throw "SSH key was not found at $KeyPath"
}

$ssh = Get-Command ssh -ErrorAction Stop
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputPath = Join-Path $OutputDirectory "vm_predeploy_$timestamp.txt"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

# This intentionally records only component states and versions. It never
# reads secret values from auth.env or Synapse configuration.
$remoteCommand = @'
set -eu
cd '{0}'
printf '%s\n' '# XMO VM pre-deployment snapshot'
printf 'captured_at_utc='; date -u +%Y-%m-%dT%H:%M:%SZ
printf 'host='; hostname
printf '\n[compose services]\n'
docker compose ps
printf '\n[compose images]\n'
docker compose images
printf '\n[configured flags]\n'
for name in XMO_OIDC_ONLY_AUTHENTICATION XMO_RECOVERY_EMAIL_STORE_FILE XMO_WALLET_JWT_ISSUER XMO_WALLET_JWT_AUDIENCE XMO_ACCOUNT_DELETION_STORE_FILE XMO_MAX_MEDIA_UPLOAD_BYTES; do
  if grep -q "^$name=" auth.env; then
    printf '%s=set\n' "$name"
  else
    printf '%s=MISSING\n' "$name"
  fi
done
printf '\n[synapse settings]\n'
grep -nE '^(max_upload_size|enable_registration|password_config:|jwt_config:|modules:)' synapse/homeserver.yaml || true
printf '\n[auth server source]\n'
if [ -f auth_server/Dockerfile ]; then sha256sum auth_server/Dockerfile; fi
if [ -d .git ]; then git rev-parse HEAD; fi
'@ -f $RemoteDirectory

& $ssh.Source `
    -o BatchMode=yes `
    -o ConnectTimeout=20 `
    -i $KeyPath `
    "$UserName@$HostName" `
    $remoteCommand | Tee-Object -FilePath $outputPath

Write-Host "Snapshot written to $outputPath"
