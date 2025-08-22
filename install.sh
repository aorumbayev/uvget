#!/bin/bash
set -euo pipefail

VERSION="0.1.0"
UV_INSTALL_URL="https://astral.sh/uv/install.sh"
PYPI_API_URL="https://pypi.org/pypi"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m' 
YELLOW='\033[0;33m'
NC='\033[0m'

usage() {
    cat << EOF
uvget v${VERSION} - Universal UV Tool Installer

Usage: $0 [OPTIONS] PACKAGE

Options:
  --with-python    Query PyPI and install compatible Python if needed
  --dry-run       Show what would be done without executing
  --help, -h      Show this help message

Examples:
  $0 black
  $0 --with-python httpie
  $0 --dry-run ruff

EOF
}

log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

die() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

validate_package() {
    local package="$1"
    [[ -n "$package" ]] || die "Package name is required"
    [[ "$package" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}[a-zA-Z0-9]$|^[a-zA-Z0-9]$ ]] || \
        die "Invalid package name. Use only letters, numbers, dots, hyphens, underscores"
    [[ ${#package} -le 64 ]] || die "Package name too long (max 64 chars)"
}

check_deps() {
    command -v curl >/dev/null || die "curl is required but not installed"
}

ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        log "UV found: $(uv --version 2>/dev/null || echo 'unknown version')"
        return 0
    fi
    
    log "Installing UV..."
    if [[ "${DRY_RUN:-}" == "true" ]]; then
        log "DRY RUN: Would install UV from $UV_INSTALL_URL"
        return 0
    fi
    
    # Download and install UV with basic verification  
    local temp_file
    temp_file=$(mktemp)
    
    if ! curl -fsSL --connect-timeout 30 --max-time 300 "$UV_INSTALL_URL" > "$temp_file"; then
        die "Failed to download UV installer"
    fi
    
    # Basic sanity checks on installer
    if [[ $(wc -c < "$temp_file") -lt 1000 ]]; then
        die "UV installer appears too small"
    fi
    
    if ! grep -q "astral" "$temp_file"; then
        die "UV installer doesn't appear to be from Astral"
    fi
    
    bash "$temp_file" || die "UV installation failed"
    
    # Clean up temp file immediately
    rm -f "$temp_file"
    
    # Update PATH for current session
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
    
    if ! command -v uv >/dev/null 2>&1; then
        die "UV installation succeeded but uv command not found. Try: source ~/.bashrc"
    fi
    
    log "UV installed successfully"
}

get_python_requirement() {
    local package="$1"
    local api_url="${PYPI_API_URL}/${package}/json"
    
    log "Checking Python requirements for $package..."
    
    if [[ "${DRY_RUN:-}" == "true" ]]; then
        log "DRY RUN: Would query $api_url"
        echo ">=3.8"  # Mock response
        return 0
    fi
    
    local json_response
    if ! json_response=$(curl -fsSL --connect-timeout 10 --max-time 30 "$api_url" 2>/dev/null); then
        warn "Could not fetch package info from PyPI, proceeding without Python check"
        return 1
    fi
    
    # Try jq first, fall back to grep
    local python_req=""
    if command -v jq >/dev/null 2>&1; then
        python_req=$(echo "$json_response" | jq -r '.info.requires_python // ""' 2>/dev/null || echo "")
    else
        # Simple grep-based extraction for common patterns
        python_req=$(echo "$json_response" | grep -o '"requires_python"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
    fi
    
    if [[ -n "$python_req" ]]; then
        log "Package requires Python: $python_req"
        echo "$python_req"
    else
        warn "No Python requirement found, assuming compatible"
        return 1
    fi
}

ensure_python() {
    local requirement="$1"
    
    # Extract minimum version (simple pattern matching)
    local min_version
    if [[ "$requirement" =~ \>\=([0-9]+\.[0-9]+) ]]; then
        min_version="${BASH_REMATCH[1]}"
    else
        min_version="3.8"  # Reasonable default
    fi
    
    log "Checking for Python $min_version+..."
    
    # Check if UV can see a compatible Python
    if uv python list 2>/dev/null | grep -q "cpython-$min_version" || \
       uv python list 2>/dev/null | grep -q "cpython-3.1[0-9]"; then
        log "Compatible Python found"
        return 0
    fi
    
    log "Installing Python $min_version via UV..."
    if [[ "${DRY_RUN:-}" == "true" ]]; then
        log "DRY RUN: Would install Python $min_version"
        return 0
    fi
    
    if ! uv python install "$min_version" 2>/dev/null; then
        warn "Failed to install Python $min_version, trying latest"
        uv python install 3.11 || die "Failed to install Python"
    fi
    
    log "Python installed successfully"
}

install_package() {
    local package="$1"
    
    log "Installing $package via UV..."
    if [[ "${DRY_RUN:-}" == "true" ]]; then
        log "DRY RUN: Would run: uv tool install $package"
        log "Installation complete!"
        return 0
    fi
    
    if ! uv tool install "$package"; then
        die "Failed to install $package"
    fi
    
    log "Successfully installed $package"
    
    # Show where it was installed
    local tool_path
    if tool_path=$(command -v "$package" 2>/dev/null); then
        log "Tool available at: $tool_path"
    else
        warn "Tool installed but not in PATH. You may need to add ~/.local/bin to your PATH"
        echo "Add this to your ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

main() {
    local package=""
    local with_python=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --with-python)
                with_python=true
                shift
                ;;
            --dry-run)
                export DRY_RUN=true
                warn "DRY RUN MODE - No changes will be made"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                [[ -z "$package" ]] || die "Multiple packages not supported"
                package="$1"
                shift
                ;;
        esac
    done
    
    [[ -n "$package" ]] || { usage; exit 1; }
    
    log "uvget v$VERSION - Installing $package"
    
    validate_package "$package"
    check_deps
    ensure_uv
    
    if [[ "$with_python" == true ]]; then
        if python_req=$(get_python_requirement "$package"); then
            ensure_python "$python_req"
        fi
    fi
    
    install_package "$package"
    log "Installation complete!"
}

main "$@"