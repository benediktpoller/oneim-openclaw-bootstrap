param(
  [Parameter(Mandatory=$true)]
  [string]$GatewayToken,

  [string]$GatewayUrl = 'ws://145.14.157.230:18789',

  [string]$NodeIdOrIp = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Node service:" -ForegroundColor Cyan
& openclaw node status | Out-Host

Write-Host "\nNodes list:" -ForegroundColor Cyan
& openclaw nodes list --url $GatewayUrl --token $GatewayToken | Out-Host

if ($NodeIdOrIp -ne '') {
  Write-Host "\nDescribe $NodeIdOrIp:" -ForegroundColor Cyan
  & openclaw nodes describe --url $GatewayUrl --token $GatewayToken --node $NodeIdOrIp | Out-Host
}
