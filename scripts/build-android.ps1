# 打包 Android APK（local / test / prod）
# 用法：.\scripts\build-android.ps1 -Env prod
# 产物：build/app/outputs/flutter-apk/app-release.apk

param(
  [ValidateSet('local', 'test', 'prod')]
  [string]$EnvName = 'prod'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
. "$PSScriptRoot\_env.ps1" -EnvName $EnvName

Write-Host ">>> flutter pub get" -ForegroundColor Green
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> flutter build apk --release ($EnvName)" -ForegroundColor Green
flutter build apk --release @PhotoLinkDefines
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apk = "build\app\outputs\flutter-apk\app-release.apk"
Write-Host "完成：$apk" -ForegroundColor Green
