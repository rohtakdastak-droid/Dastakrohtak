$ErrorActionPreference='Stop'
$mobileRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source=Join-Path $mobileRoot 'config/routes.private.env'
if (!(Test-Path -LiteralPath $source)) { throw 'Save the Routes API key in config/routes.private.env first.' }
$values=Get-Content -LiteralPath $source -Raw | ConvertFrom-StringData
$routeKey=([string]$values['GOOGLE_ROUTES_API_KEY']).Trim()
if ($routeKey -notmatch '^AIza[A-Za-z0-9_-]{35}$') { throw 'GOOGLE_ROUTES_API_KEY has an invalid format; value not displayed.' }
$temporary=Join-Path $mobileRoot 'config/routes-upload.private.env'
try {
  Set-Content -LiteralPath $temporary -Value "GOOGLE_ROUTES_API_KEY=$routeKey"
  Push-Location (Join-Path $mobileRoot '..')
  try {
    & supabase secrets set --env-file $temporary
    if ($LASTEXITCODE -ne 0) { throw 'Routes secret deployment failed.' }
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
}
$push=Get-Content (Join-Path $mobileRoot 'config/push.private.env') -Raw | ConvertFrom-StringData
$config=Get-Content (Join-Path $mobileRoot 'config/local.json') -Raw | ConvertFrom-Json
$response=Invoke-RestMethod -Method Post -Uri ($config.SUPABASE_URL.TrimEnd('/')+'/functions/v1/place-order?health=1') -Headers @{Authorization=('Bearer '+$push['PUSH_WEBHOOK_TOKEN'])}
if (!$response.routing_ready) { throw 'Google Routes provider check failed.' }
Write-Output 'Google Routes live calculation passed. Checkout routing is ready.'
