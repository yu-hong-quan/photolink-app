# 打包 Android App Bundle（上架用）
# 用法：.\scripts\build-android-aab.ps1 -Env prod

param(
  [ValidateSet('local', 'test', 'prod')]
  [string]$EnvName = 'prod'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
. "$PSScriptRoot\_env.ps1" -EnvName $EnvName

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter build appbundle --release @PhotoLinkDefines
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "完成：build\app\outputs\bundle\release\app-release.aab" -ForegroundColor Green
