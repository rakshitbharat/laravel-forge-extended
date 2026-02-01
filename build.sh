#!/bin/bash

# Build Script for Laravel Forge Extended
# Combines source files into distributable scripts

set -e

# ==============================================================================
# Build Configuration
# ==============================================================================

BUILD_TARGETS=(
    # Format: "bash_source|python_source|output"
    "src/bash/bootstrap.sh|src/python/automator.py|dist/automator.sh"
    "src/bash/cloudflare-dns.sh|src/python/cloudflare-automator.py|dist/cloudflare-dns-setup.sh"
)

# Standalone scripts (no Python embedding needed)
STANDALONE_TARGETS=(
    "src/bash/cleanup.sh|dist/cleanup.sh"
)

# ==============================================================================
# Build Function
# ==============================================================================

build_script() {
    local bash_src="$1"
    local python_src="$2"
    local output="$3"
    
    echo "Building $output..."
    
    # Check if source files exist
    if [ ! -f "$bash_src" ]; then
        echo "ERROR: Bash source not found: $bash_src"
        return 1
    fi
    
    if [ ! -f "$python_src" ]; then
        echo "ERROR: Python source not found: $python_src"
        return 1
    fi
    
    # Create dist directory if it doesn't exist
    mkdir -p "$(dirname "$output")"
    
    # Build: Replace {{PYTHON_SCRIPT}} placeholder with actual Python script
    awk 'FNR==NR{a[NR]=$0; len=NR; next} /{{PYTHON_SCRIPT}}/{for (i=1;i<=len;i++) print a[i]; next} 1' \
        "$python_src" "$bash_src" > "$output"
    
    # Make executable
    chmod +x "$output"
    
    echo "✓ Build complete: $output"
}

# ==============================================================================
# Main Execution
# ==============================================================================

echo "=================================================================="
echo " Building Laravel Forge Extended Scripts"
echo "=================================================================="
echo ""

# Build all targets
for target in "${BUILD_TARGETS[@]}"; do
    IFS='|' read -r bash_src python_src output <<< "$target"
    build_script "$bash_src" "$python_src" "$output"
    echo ""
done

# Build standalone scripts (simple copy)
for target in "${STANDALONE_TARGETS[@]}"; do
    IFS='|' read -r source output <<< "$target"
    echo "Building $output..."
    
    if [ ! -f "$source" ]; then
        echo "ERROR: Source not found: $source"
        continue
    fi
    
    mkdir -p "$(dirname "$output")"
    cp "$source" "$output"
    chmod +x "$output"
    
    echo "✓ Build complete: $output"
    echo ""
done

echo "=================================================================="
echo " All builds completed successfully!"
echo "=================================================================="
echo ""
echo "Output files:"
for target in "${BUILD_TARGETS[@]}"; do
    IFS='|' read -r bash_src python_src output <<< "$target"
    if [ -f "$output" ]; then
        size=$(wc -c < "$output" | tr -d ' ')
        echo "  ✓ $output (${size} bytes)"
    fi
done
echo ""
