[CmdletBinding()]
param(
  [switch]$PromoteProduction
)

$ErrorActionPreference = 'Stop'

$backendRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configPath = Join-Path $backendRoot 'wrangler.jsonc'
$wranglerPath = Join-Path $backendRoot 'node_modules\.bin\wrangler.cmd'
$originalBaseUrl = $env:BASE_URL

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
  throw 'Node.js 26 or newer is required.'
}
$nodeVersion = [version](node.exe -p 'process.versions.node')
if ($nodeVersion.Major -lt 26) {
  throw "Node.js 26 or newer is required; found $nodeVersion."
}
if (-not (Test-Path $wranglerPath)) {
  throw 'Wrangler is not installed. Run npm ci in duka_pos_backend first.'
}

Push-Location $backendRoot
try {
  Write-Host 'Running backend tests...'
  & npm.cmd test
  if ($LASTEXITCODE -ne 0) {
    throw 'Backend tests failed; deployment was stopped.'
  }

  Write-Host 'Building backend...'
  & npm.cmd run build
  if ($LASTEXITCODE -ne 0) {
    throw 'Backend build failed; deployment was stopped.'
  }

  Write-Host 'Checking Wrangler authentication...'
  & $wranglerPath whoami --config $configPath *> $null
  if ($LASTEXITCODE -ne 0) {
    throw 'Wrangler is not authenticated. Run "wrangler login" interactively, then retry.'
  }

  Write-Host 'Verifying the staging D1 schema...'
  & node.exe scripts/check-d1-schema.mjs --remote --env staging
  if ($LASTEXITCODE -ne 0) {
    throw 'Staging D1 schema check failed; production migration and deployment were stopped.'
  }

  $transactionSites = Get-ChildItem -Path (Join-Path $backendRoot 'src\routes') -Filter '*.ts' -File -Recurse |
    Select-String -Pattern '\.\$transaction\s*\('
  if ($transactionSites) {
    $siteList = @($transactionSites | ForEach-Object {
      $relativePath = $_.Path.Substring($backendRoot.Length + 1)
      "${relativePath}:$($_.LineNumber)"
    }) -join [Environment]::NewLine
    throw "D1 deployment is blocked: the Prisma D1 adapter does not provide transaction atomicity. Refactor and test every remaining transaction before release.`n$siteList"
  }

  if (-not $PromoteProduction) {
    Write-Host 'Preflight checks passed. Production D1 and the Worker were not changed.'
    Write-Host 'Use -PromoteProduction to run staging live journeys and promote only if they pass.'
    return
  }

  if (-not $env:STAGING_BASE_URL) {
    throw 'Set STAGING_BASE_URL to the HTTPS origin of the staging Worker before production promotion.'
  }
  $stagingUri = [Uri]$env:STAGING_BASE_URL
  if ($stagingUri.Scheme -ne 'https' -or $stagingUri.Host -ne 'duka-pos-backend-staging.brianbmk332.workers.dev' -or $stagingUri.AbsolutePath -ne '/') {
    throw 'STAGING_BASE_URL must be the configured HTTPS staging Worker origin with no path.'
  }
  if (-not $env:STAGING_AUTH_TEST_SECRET) {
    throw 'Set STAGING_AUTH_TEST_SECRET for the restricted staging auth journey.'
  }
  $env:BASE_URL = $stagingUri.GetLeftPart([UriPartial]::Authority)

  Write-Host 'Checking the restricted staging auth secret name...'
  $stagingSecretOutput = & $wranglerPath secret list --env staging --config $configPath --format json 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not list staging Worker secret names. Deployment was stopped.'
  }
  try {
    $stagingSecrets = ($stagingSecretOutput -join [Environment]::NewLine) | ConvertFrom-Json
  } catch {
    throw 'Could not read the staging Worker secret-name list. Deployment was stopped.'
  }
  $stagingSecretNames = @($stagingSecrets | ForEach-Object { $_.name })
  if ('STAGING_AUTH_TEST_SECRET' -notin $stagingSecretNames) {
    throw 'The restricted staging auth secret is missing from the staging Worker.'
  }

  Write-Host 'Running credential-free live smoke checks against staging...'
  & npm.cmd run test:live
  if ($LASTEXITCODE -ne 0) {
    throw 'Staging live smoke failed; production migration and deployment were stopped.'
  }

  Write-Host 'Running authenticated staging journeys...'
  foreach ($journey in @('test:live:auth', 'test:live:analytics', 'test:live:backup')) {
    & npm.cmd run $journey
    if ($LASTEXITCODE -ne 0) {
      throw "Staging journey $journey failed; production migration and deployment were stopped."
    }
  }

  Write-Host 'Checking required Worker secrets (names only)...'
  $secretOutput = & $wranglerPath secret list --config $configPath --format json 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not list Worker secret names. Deployment was stopped.'
  }
  try {
    $secrets = ($secretOutput -join [Environment]::NewLine) | ConvertFrom-Json
  } catch {
    throw 'Could not read the Worker secret-name list. Deployment was stopped.'
  }
  $secretNames = @($secrets | ForEach-Object { $_.name })
  $requiredSecrets = @('AUTH_JWT_SECRET', 'EMAIL_VERIFICATION_SECRET')
  $missingSecrets = @($requiredSecrets | Where-Object { $_ -notin $secretNames })
  if ($missingSecrets.Count -gt 0) {
    throw "Required Worker secrets are missing: $($missingSecrets -join ', '). Add them in the Cloudflare dashboard; values are never read by this script."
  }

  Write-Host 'Validating the production Worker bundle...'
  & $wranglerPath deploy --dry-run --env '' --config $configPath
  if ($LASTEXITCODE -ne 0) {
    throw 'Production Worker dry-run failed; production migration and deployment were stopped.'
  }

  Write-Host 'Applying D1 migrations to production...'
  & $wranglerPath d1 migrations apply duka-pos-prod --remote --config $configPath
  if ($LASTEXITCODE -ne 0) {
    throw 'Production D1 migrations failed; Worker deployment was stopped.'
  }
  & node.exe scripts/check-d1-schema.mjs --remote
  if ($LASTEXITCODE -ne 0) {
    throw 'Production D1 schema check failed; Worker deployment was stopped.'
  }

  Write-Host 'Verification passed. Deploying the backend Worker...'
  & $wranglerPath deploy --config $configPath
  if ($LASTEXITCODE -ne 0) {
    throw 'Wrangler deployment failed.'
  }
} finally {
  if ($null -eq $originalBaseUrl) {
    Remove-Item Env:\BASE_URL -ErrorAction SilentlyContinue
  } else {
    $env:BASE_URL = $originalBaseUrl
  }
  Pop-Location
}
