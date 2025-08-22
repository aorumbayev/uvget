[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$PackageName,
    
    [switch]$WithPython,
    [switch]$DryRun,
    [switch]$Help
)

$VERSION = "0.1.0"
$UV_INSTALL_URL = "https://astral.sh/uv/install.ps1"
$PYPI_API_URL = "https://pypi.org/pypi"

function Show-Usage {
    @"
uvget v$VERSION - Universal UV Tool Installer

Usage: .\install.ps1 [-WithPython] [-DryRun] [-Help] PackageName

Options:
  -WithPython    Query PyPI and install compatible Python if needed
  -DryRun       Show what would be done without executing
  -Help         Show this help message

Examples:
  .\install.ps1 black
  .\install.ps1 -WithPython httpie
  .\install.ps1 -DryRun ruff
"@
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $color = switch ($Level) {
        "INFO" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Stop-WithError {
    param([string]$Message)
    Write-Log $Message "ERROR"
    exit 1
}

function Test-PackageName {
    param([string]$Package)
    
    if ([string]::IsNullOrWhiteSpace($Package)) {
        Stop-WithError "Package name is required"
    }
    
    if ($Package.Length -gt 64) {
        Stop-WithError "Package name too long (max 64 chars)"
    }
    
    if (-not ($Package -match '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}[a-zA-Z0-9]$|^[a-zA-Z0-9]$')) {
        Stop-WithError "Invalid package name. Use only letters, numbers, dots, hyphens, underscores"
    }
}

function Ensure-UV {
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        $uvVersion = (uv --version 2>$null) -replace 'uv ', '' -replace '\n', ''
        Write-Log "UV found: uv $uvVersion"
        return
    }
    
    Write-Log "Installing UV..."
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would install UV from $UV_INSTALL_URL"
        return
    }
    
    try {
        # Use the official PowerShell installer
        Invoke-RestMethod $UV_INSTALL_URL | Invoke-Expression
        
        # Update PATH for current session
        $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:USERPROFILE\.local\bin;$env:PATH"
        
        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            Stop-WithError "UV installation succeeded but uv command not found. Try restarting your shell"
        }
        
        Write-Log "UV installed successfully"
    }
    catch {
        Stop-WithError "Failed to install UV: $($_.Exception.Message)"
    }
}

function Get-PythonRequirement {
    param([string]$Package)
    
    Write-Log "Checking Python requirements for $Package..."
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would query $PYPI_API_URL/$Package/json"
        return ">=3.8"
    }
    
    try {
        $response = Invoke-RestMethod -Uri "$PYPI_API_URL/$Package/json" -TimeoutSec 10
        $pythonReq = $response.info.requires_python
        
        if ($pythonReq) {
            Write-Log "Package requires Python: $pythonReq"
            return $pythonReq
        } else {
            Write-Log "No Python requirement found, assuming compatible" "WARN"
            return $null
        }
    }
    catch {
        Write-Log "Could not fetch package info from PyPI, proceeding without Python check" "WARN"
        return $null
    }
}

function Ensure-Python {
    param([string]$Requirement)
    
    # Extract minimum version
    $minVersion = if ($Requirement -match '>=(\d+\.\d+)') { $matches[1] } else { "3.8" }
    
    Write-Log "Checking for Python $minVersion+..."
    
    # Check if UV can see a compatible Python
    try {
        $pythonList = uv python list 2>$null | Out-String
        if ($pythonList -match "cpython-$minVersion" -or $pythonList -match "cpython-3\.1\d") {
            Write-Log "Compatible Python found"
            return
        }
    }
    catch {
        # Ignore errors
    }
    
    Write-Log "Installing Python $minVersion via UV..."
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would install Python $minVersion"
        return
    }
    
    try {
        uv python install $minVersion 2>$null
        Write-Log "Python installed successfully"
    }
    catch {
        Write-Log "Failed to install Python $minVersion, trying latest" "WARN"
        try {
            uv python install 3.11
            Write-Log "Python installed successfully"
        }
        catch {
            Stop-WithError "Failed to install Python"
        }
    }
}

function Install-Package {
    param([string]$Package)
    
    Write-Log "Installing $Package via UV..."
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would run: uv tool install $Package"
        Write-Log "Installation complete!"
        return
    }
    
    try {
        uv tool install $Package
        Write-Log "Successfully installed $Package"
        
        # Show where it was installed
        $toolPath = Get-Command $Package -ErrorAction SilentlyContinue
        if ($toolPath) {
            Write-Log "Tool available at: $($toolPath.Source)"
        } else {
            Write-Log "Tool installed but not in PATH. You may need to restart your shell" "WARN"
        }
    }
    catch {
        Stop-WithError "Failed to install ${Package}: $($_.Exception.Message)"
    }
}

# Main execution
if ($Help) {
    Show-Usage
    exit 0
}

if ([string]::IsNullOrWhiteSpace($PackageName)) {
    Show-Usage
    exit 1
}

$ErrorActionPreference = "Stop"

try {
    if ($DryRun) {
        Write-Log "DRY RUN MODE - No changes will be made" "WARN"
    }
    
    Write-Log "uvget v$VERSION - Installing $PackageName"
    
    Test-PackageName $PackageName
    Ensure-UV
    
    if ($WithPython) {
        $pythonReq = Get-PythonRequirement $PackageName
        if ($pythonReq) {
            Ensure-Python $pythonReq
        }
    }
    
    Install-Package $PackageName
    Write-Log "Installation complete!"
}
catch {
    Write-Log "Unexpected error: $($_.Exception.Message)" "ERROR"
    exit 1
}