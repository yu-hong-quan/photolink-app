# PhotoLink 打包环境说明
#
# 通过 --dart-define=FLAVOR=local|test|prod 切换：
#   local  相册 53337 / 配对 53338（本地调试）
#   test   相册 53327 / 配对 53328（测试）
#   prod   相册 53317 / 配对 53318（生产，默认）
#
# App 与 PC 必须使用同一 FLAVOR，否则端口对不上无法配对。

param(
  [ValidateSet('local', 'test', 'prod')]
  [string]$EnvName = 'prod'
)

$script:PhotoLinkDefines = @(
  "--dart-define=FLAVOR=$EnvName"
)

Write-Host "PhotoLink FLAVOR=$EnvName" -ForegroundColor Cyan
Write-Host ("Defines: " + ($PhotoLinkDefines -join ' '))
