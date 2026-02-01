#!/bin/bash

# Laravel Forge Extended - Full Deployment Automator
# Usage: curl -sL <url> | bash

set -e

# ==============================================================================
# 1. Environment Detection
# ==============================================================================
IS_FORGE="false"
if [ -n "$FORGE_SITE_PATH" ]; then
    IS_FORGE="true"
fi

# Defaults
SITE_PATH="${FORGE_SITE_PATH:-$(pwd)}"
PHP_BIN="${FORGE_PHP:-php}"
COMPOSER_BIN="${FORGE_COMPOSER:-composer}"
BRANCH="${FORGE_SITE_BRANCH:-main}"
REPO_URL="${FORGE_REPO_URL:-}"

# Zero Downtime Detection
USE_ZDT="false"
ROOT_PATH="$SITE_PATH"

if [ -d "$SITE_PATH/../releases" ]; then
    USE_ZDT="true"
    ROOT_PATH="$(dirname "$SITE_PATH")"
elif [ -d "$SITE_PATH/releases" ]; then
    USE_ZDT="true"
    ROOT_PATH="$SITE_PATH"
fi

# Timestamp for release
TIMESTAMP=$(date +%Y%m%d%H%M%S)

log() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# ==============================================================================
# 2. Deployment Logic
# ==============================================================================

deploy_standard() {
    log "Starting Standard Deployment..."
    cd "$SITE_PATH"

    # Check if we are in a git repo
    SKIP_GIT="false"
    
    if [ ! -d ".git" ]; then
        # fallback to FORGE_SITE_REPO if available
        if [ -z "$REPO_URL" ] && [ -n "$FORGE_SITE_REPO" ]; then
            REPO_URL="git@github.com:$FORGE_SITE_REPO"
            # Or https if preferred/configured, but usually forge is git@...
            # Actually, FORGE_SITE_REPO might be "user/repo".
            # Let's try to infer full URL if it looks like user/repo
            if [[ "$FORGE_SITE_REPO" != *" "* ]] && [[ "$FORGE_SITE_REPO" != *":"* ]]; then
                 REPO_URL="https://github.com/$FORGE_SITE_REPO.git"
            fi
        fi

        if [ -n "$REPO_URL" ]; then
            log "No git repository found. Cloning from $REPO_URL..."
            # Check if dir is empty or safe to clone into
            if [ "$(ls -A .)" ]; then
                 log "Directory not empty. Attempting to initialize and pull..."
                 git init
                 git remote add origin "$REPO_URL"
                 git fetch origin
                 git checkout -t "origin/$BRANCH" || git checkout "$BRANCH"
            else
                 git clone -b "$BRANCH" "$REPO_URL" .
            fi
        else
            # Check for non-git project (Manual Upload)
            if [ -f "artisan" ]; then
                log "Warning: Not a git repository, but 'artisan' file detected."
                log "Assume Manual Upload / Non-Git Project. Skipping Git Operations."
                SKIP_GIT="true"
            else
                error "Fatal: Not a git repository and FORGE_REPO_URL not set."
                error "Current Directory: $(pwd)"
                error "Please run inside a git repo or set FORGE_REPO_URL='...'"
                exit 1
            fi
        fi
    fi

    if [ "$SKIP_GIT" != "true" ]; then
        log "Pulling Code from $BRANCH..."
        git reset --hard HEAD
        git pull origin "$BRANCH"
    else
        log "Skipping Git Pull (Non-Git Project detected)"
    fi

    run_build_steps "$SITE_PATH"
    
    finalize_deployment
}

deploy_zero_downtime() {
    log "Starting Zero-Downtime Deployment..."
    
    # Setup shared directory structure
    SHARED_PATH="$ROOT_PATH/shared"
    mkdir -p "$SHARED_PATH"
    
    # Handle .env file in shared directory
    if [ ! -f "$SHARED_PATH/.env" ]; then
        log "No .env found in shared directory. Checking for existing .env..."
        
        # Try to copy from current release
        if [ -L "$ROOT_PATH/current" ] && [ -f "$ROOT_PATH/current/.env" ]; then
            log "Copying .env from current release to shared..."
            cp "$ROOT_PATH/current/.env" "$SHARED_PATH/.env"
        elif [ -f "$SITE_PATH/.env" ]; then
            log "Copying .env from SITE_PATH to shared..."
            cp "$SITE_PATH/.env" "$SHARED_PATH/.env"
        else
            error "CRITICAL: No .env file found!"
            error "Please create $SHARED_PATH/.env before deploying."
            error "You can use: cp .env.example $SHARED_PATH/.env"
            error "Then configure it with your production credentials."
            exit 1
        fi
    fi
    
    # Setup shared storage directory
    mkdir -p "$SHARED_PATH/storage/app"
    mkdir -p "$SHARED_PATH/storage/framework/cache"
    mkdir -p "$SHARED_PATH/storage/framework/sessions"
    mkdir -p "$SHARED_PATH/storage/framework/views"
    mkdir -p "$SHARED_PATH/storage/logs"
    
    # Copy existing storage if it doesn't exist in shared
    if [ -d "$SITE_PATH/storage" ] && [ ! "$(ls -A $SHARED_PATH/storage/app 2>/dev/null)" ]; then
        log "Migrating storage contents to shared directory..."
        cp -rn "$SITE_PATH/storage/"* "$SHARED_PATH/storage/" 2>/dev/null || true
    fi
    
    NEW_RELEASE_PATH="$ROOT_PATH/releases/$TIMESTAMP"
    log "Creating Release: $NEW_RELEASE_PATH"
    mkdir -p "$NEW_RELEASE_PATH"
    
    # Git Clone / Copy
    # We use a robust method: Get Remote URL and Clone
    DETECTED_URL=$(git -C "$ROOT_PATH" config --get remote.origin.url || git -C "$SITE_PATH" config --get remote.origin.url || echo "")
    
    if [ -n "$DETECTED_URL" ]; then
        REPO_URL="$DETECTED_URL"
    fi

    if [ -z "$REPO_URL" ]; then
        error "Could not detect Git Repository URL. Falling back to Standard Deployment."
        deploy_standard
        return
    fi
    
    log "Cloning $REPO_URL..."
    # Shallow clone for speed
    git clone -b "$BRANCH" --depth 1 "$REPO_URL" "$NEW_RELEASE_PATH" || \
    git clone -b "$BRANCH" "$REPO_URL" "$NEW_RELEASE_PATH"
    
    cd "$NEW_RELEASE_PATH"

        elif [ -f "$ROOT_PATH/current/.env" ]; then
            ENV_SOURCE="$ROOT_PATH/current/.env"
        fi
        
        if [ -n "$ENV_SOURCE" ]; then
            log "Copying existing .env to shared location..."
            cp "$ENV_SOURCE" "$SHARED_PATH/.env"
        else
            log "WARNING: No .env file found in shared location or previous releases." "WARN"
            log "Please ensure $SHARED_PATH/.env exists before deployment continues." "WARN"
            log "You can create it manually or copy from .env.example" "WARN"
        fi
    fi
    
    # Symlink .env from shared to current release
    if [ -f "$SHARED_PATH/.env" ]; then
        log "Symlinking .env from shared location..."
        ln -nfs "$SHARED_PATH/.env" "$NEW_RELEASE_PATH/.env"
    else
        error "CRITICAL: $SHARED_PATH/.env does not exist!"
        error "Zero-downtime deployments require a shared .env file."
        error "Please create $SHARED_PATH/.env manually or run standard deployment first."
        exit 1
    fi
    
    # Also handle storage directory as shared resource
    SHARED_STORAGE="$SHARED_PATH/storage"
    if [ ! -d "$SHARED_STORAGE" ]; then
        log "Initializing shared storage directory..."
        mkdir -p "$SHARED_STORAGE"/{app,framework,logs}
        mkdir -p "$SHARED_STORAGE/framework"/{cache,sessions,testing,views}
        
        # Copy from old release if exists
        if [ -d "$ROOT_PATH/current/storage" ]; then
            log "Migrating storage from previous release..."
            cp -r "$ROOT_PATH/current/storage"/* "$SHARED_STORAGE/" 2>/dev/null || true
        fi
    fi
    
    # Remove release's storage directory and symlink to shared
    if [ -d "$NEW_RELEASE_PATH/storage" ]; then
        rm -rf "$NEW_RELEASE_PATH/storage"
    fi
    ln -nfs "$SHARED_STORAGE" "$NEW_RELEASE_PATH/storage"
    # -------------------------------------------

    run_build_steps "$NEW_RELEASE_PATH"

    # Activate Release
    log "Activating Release..."
    ln -nfs "$NEW_RELEASE_PATH" "$ROOT_PATH/current"
    
    finalize_deployment
    
    # Cleanup Old Releases (Keep 5)
    log "Cleaning old releases..."
    cd "$ROOT_PATH/releases"
    ls -1t | tail -n +6 | xargs rm -rf
}

run_build_steps() {
    local TARGET_PATH="$1"
    
    # --- Local Environment Guard ---
    if [ "$IS_FORGE" != "true" ]; then
        log "Local environment detected. Skipping build commands (composer, npm, artisan)."
        log "To force execution, set FORGE_SITE_PATH or run on Forge."
        return
    fi
    # -------------------------------

    cd "$TARGET_PATH"
    
    # --- .ENV Validation ---
    if [ ! -f ".env" ]; then
        error "CRITICAL: .env file not found in $TARGET_PATH"
        error "Deployment cannot proceed without database credentials."
        error "Please ensure a valid .env file is present or correct the deployment path."
        exit 1
    fi
    # -----------------------

    log "Installing Composer Dependencies..."
    $COMPOSER_BIN install --no-dev --no-interaction --prefer-dist --optimize-autoloader

    # --- PYTHON AUTOMATOR EXECUTION ---
    log "Running Auto-Fixer (Python)..."
    run_python_automator "$TARGET_PATH"
    # ----------------------------------
    
    # Build Assets
    if [ -f "package.json" ]; then
        log "Building Assets..."
        
        if [ -f "package-lock.json" ]; then
            log "package-lock.json found. Running npm ci..."
            npm ci
        else
            log "No package-lock.json found. Running npm install..."
            npm install
        fi
        
        if python3 -c "import json, sys; data = json.load(open('package.json')); sys.exit(0 if 'build' in data.get('scripts', {}) else 1)"; then
             npm run build
        elif python3 -c "import json, sys; data = json.load(open('package.json')); sys.exit(0 if 'production' in data.get('scripts', {}) else 1)"; then
             npm run production
        elif python3 -c "import json, sys; data = json.load(open('package.json')); sys.exit(0 if 'prod' in data.get('scripts', {}) else 1)"; then
             npm run prod
        else
             log "No 'build', 'production', or 'prod' script found in package.json. Skipping asset build." "WARN"
        fi
    fi
    
    log "Migrating Database..."
    $PHP_BIN artisan migrate --force
}

finalize_deployment() {
    # Reload FPM
    # Attempt to reload using passwordless sudo if available (standard Forge)
    # Check if sudo is functional first to avoid crashing on system errors (e.g. broken permission bits)
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        ( flock -w 10 9 || exit 1
            echo 'Restarting FPM...'; sudo -S service $FORGE_PHP_FPM reload || echo "FPM reload failed (sudo error)" ) 9>/tmp/fpmlock || log "FPM Reload prevented by lock or error." "WARN"
    else
        log "Sudo is not available or functional. Skipping FPM reload." "WARN"
    fi
    
    # Restart Queue
    if [ -f artisan ]; then
        $PHP_BIN artisan queue:restart
    fi
}

run_python_automator() {
    local TARGET="$1"
    local SCRIPT=".automator_core.py"
    
    # EMBEDDED_PYTHON_START
    cat << 'EOF_PYTHON' > "$TARGET/$SCRIPT"
{{PYTHON_SCRIPT}}
EOF_PYTHON
    # EMBEDDED_PYTHON_END
    
    cd "$TARGET"
    python3 "$SCRIPT"
    rm -f "$SCRIPT"
}

# ==============================================================================
# 3. Execution Entry Point
# ==============================================================================

echo "🚀 Starting Deployment Automator..."

if [ "$USE_ZDT" = "true" ]; then
    deploy_zero_downtime
else
    deploy_standard
fi

success "Deployment Finished!"
