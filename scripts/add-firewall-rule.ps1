$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run PowerShell as Administrator, then run this script again."
}

$displayName = "AudioBridge UDP Receiver"
$existingRule = Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue
if ($null -eq $existingRule) {
    New-NetFirewallRule `
        -DisplayName $displayName `
        -Direction Inbound `
        -Action Allow `
        -Protocol UDP `
        -LocalPort 43120 `
        -Profile Private | Out-Null
    Write-Host "Allowed inbound AudioBridge traffic on UDP 43120 for private networks."
} else {
    Write-Host "The AudioBridge firewall rule already exists."
}
