#!/bin/bash

# Laravel Forge Extended - Cloudflare DNS Setup
# Usage: curl -sL <url> | bash
# Or: bash cloudflare-dns-setup.sh

set -e

# ==============================================================================
# Environment Detection
# ==============================================================================

SITE_PATH="${FORGE_SITE_PATH:-$(pwd)}"

# ==============================================================================
# Embedded Python Script Execution
# ==============================================================================

run_cloudflare_automator() {
    local SCRIPT=".cloudflare_automator.py"
    
    # EMBEDDED_PYTHON_START
    cat <<'EOF_PYTHON' > "$SITE_PATH/$SCRIPT"
{{PYTHON_SCRIPT}}
EOF_PYTHON
    # EMBEDDED_PYTHON_END
    
    cd "$SITE_PATH"
    python3 "$SCRIPT"
    local exit_code=$?
    rm -f "$SCRIPT"
    
    return $exit_code
}

# ==============================================================================
# Main Execution
# ==============================================================================

echo "=================================================================="
echo " Cloudflare DNS Automator for Laravel Forge Extended"
echo "=================================================================="
echo ""

# Run the Python automator
run_cloudflare_automator

exit $?
