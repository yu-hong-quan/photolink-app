# 运行 Android 调试（指定环境）
# 用法：.\scripts\run-android.ps1 -Env local

param(
  [ValidateSet('local', 'test', 'prod')]
  [string]$EnvName = 'local'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
. "$PSScriptRoot\_env.ps1" -EnvName $EnvName

flutter pub get
flutter run @PhotoLinkDefines
