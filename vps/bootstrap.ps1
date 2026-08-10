# bootstrap.ps1 — run as Administrator on the Windows VPS.
# Idempotent: safe to re-run after a reboot or a failed run.
#
# Usage:
#   .\bootstrap.ps1 -VpnSubnet "100.64.0.0/10"     # Tailscale CGNAT range, example only
#
# The MCP port is opened to the VPN subnet ONLY. There is no supported way to run
# this script that exposes it to 0.0.0.0/0 — see SECURITY.md.

param(
    [Parameter(Mandatory = $true)]
    [string]$VpnSubnet,

    [int]$McpPort = 8080
)

$ErrorActionPreference = "Stop"

Write-Host "== MT5 Agentic Trading VPS Bootstrap =="

if ($VpnSubnet -match '^0\.0\.0\.0' -or $VpnSubnet -eq '*' -or $VpnSubnet -eq 'Any') {
    throw "Refusing to run: -VpnSubnet must be your private VPN CIDR, never a public/any address."
}

# --- 1. Administrator check -------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Run this script from an elevated (Administrator) PowerShell." }

# --- 2. Python --------------------------------------------------------------
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Python 3.11..."
    winget install -e --id Python.Python.3.11 --accept-source-agreements --accept-package-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
} else {
    Write-Host "Python already present: $((python --version) 2>&1)"
}

# --- 3. Project dependencies ------------------------------------------------
$repoRoot = Split-Path -Parent $PSScriptRoot
$reqFile  = Join-Path $repoRoot "orchestration\requirements.txt"
if (-not (Test-Path $reqFile)) { throw "Could not find $reqFile — run this from inside the repo." }

python -m pip install --upgrade pip
python -m pip install -r $reqFile

# --- 4. Firewall: MCP port, VPN subnet only ---------------------------------
$ruleName = "MT5-MCP-VPN-Only"
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Firewall rule '$ruleName' exists — updating remote address to $VpnSubnet"
    Set-NetFirewallRule -DisplayName $ruleName -RemoteAddress $VpnSubnet -LocalPort $McpPort
} else {
    Write-Host "Creating firewall rule '$ruleName' for $VpnSubnet on port $McpPort"
    New-NetFirewallRule -DisplayName $ruleName `
        -Direction Inbound -LocalPort $McpPort -Protocol TCP `
        -RemoteAddress $VpnSubnet -Action Allow | Out-Null
}

# --- 5. Remaining manual steps ---------------------------------------------
Write-Host ""
Write-Host "== Bootstrap complete. Remaining manual steps: =="
Write-Host "1. Install the MT5 terminal and log in to your broker account (GUI)"
Write-Host "2. Tools > Options > Expert Advisors: configure per mt5-agentic-setup.md section 2.2"
Write-Host "3. Copy .env.example to .env and fill in real credentials (type them here, never paste into a chat)"
Write-Host "4. Copy mql5\ contents into the terminal's MQL5\Experts and MQL5\Include folders"
Write-Host "5. Start the MCP server: metatrader-mcp-server --login <MT5_LOGIN> ..."
