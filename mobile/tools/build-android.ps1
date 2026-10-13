param(
  [ValidateSet('debug','release','bundle')][string]$Mode='debug',
  [string]$Config='config/local.json',
  [string]$Jdk='C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot'
)
$ErrorActionPreference='Stop'
$mobileRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configPath=Join-Path $mobileRoot $Config
if (!(Test-Path -LiteralPath $configPath)) {throw "Configuration file missing: $Config"}
$settings=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$defines=($settings.PSObject.Properties | ForEach-Object {
  [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($_.Name)=$($_.Value)"))
}) -join ','
$task=switch($Mode){'debug'{'assembleDebug'} 'release'{'assembleRelease'} 'bundle'{'bundleRelease'}}
Push-Location (Join-Path $mobileRoot 'android')
try {
  & (Join-Path $Jdk 'bin/java.exe') -classpath gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain $task --no-daemon --console=plain "-Pdart-defines=$defines"
  if($LASTEXITCODE -ne 0){throw "Android build failed ($LASTEXITCODE)"}
} finally {Pop-Location}
