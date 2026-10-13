$ErrorActionPreference = 'Stop'
$repoDir = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$entries = @{}
Get-Content -LiteralPath (Join-Path $repoDir '.env.local') | ForEach-Object {
  if ($_ -match '^(VITE_SUPABASE_URL|VITE_SUPABASE_ANON_KEY)=(.*)$') {
    $entries[$matches[1]] = $matches[2].Trim().Trim('"').Trim("'")
  }
}
if (!$entries['VITE_SUPABASE_URL'] -or !$entries['VITE_SUPABASE_ANON_KEY']) {
  throw 'Existing client Supabase configuration was not found.'
}
@{
  SUPABASE_URL = $entries['VITE_SUPABASE_URL']
  SUPABASE_ANON_KEY = $entries['VITE_SUPABASE_ANON_KEY']
  APP_ENV = 'existing-backend'
  PUSH_ENABLED = 'false'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $repoDir 'mobile/config/local.json')
Write-Output 'Client-safe config written to ignored mobile/config/local.json; no secrets printed.'
