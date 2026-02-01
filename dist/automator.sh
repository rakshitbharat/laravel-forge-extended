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
import os
import sys
import subprocess
import shutil
import pwd
import grp

# --- Configuration & Context ---
BASE_PATH = os.getcwd() 
FORGE_PHP = os.environ.get('FORGE_PHP', 'php')
FORGE_USER = os.environ.get('FORGE_USER', 'forge')
WEB_USER = 'www-data' 

def log(msg, level="INFO"):
    colors = {
        "INFO": "\033[0;34m",    # Blue
        "SUCCESS": "\033[0;32m", # Green
        "WARN": "\033[1;33m",    # Yellow
        "ERROR": "\033[0;31m",   # Red
        "RESET": "\033[0m"
    }
    print(f"{colors.get(level, '')}[{level}] {msg}{colors['RESET']}")

def run_cmd(cmd, check=False, shell=False):
    try:
        if isinstance(cmd, str) and not shell:
            cmd = cmd.split()
        
        # Use shell=True if complex command string
        result = subprocess.run(
            cmd, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE, 
            text=True, 
            cwd=BASE_PATH,
            shell=shell
        )
        if check and result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, cmd, result.stdout, result.stderr)
        return True, result.stdout.strip(), result.stderr.strip()
    except Exception as e:
        return False, "", str(e)

def detect_web_user():
    candidates = ['www-data', 'nginx', 'apache']
    for user in candidates:
        try:
            pwd.getpwnam(user)
            return user
        except KeyError:
            continue
    return 'www-data'

def fix_permissions():
    log("Running Permission Fixes...", "INFO")
    
    # 1. Determine Users
    try:
        # Just resolve strictly to ensure they exist
        pwd.getpwnam(FORGE_USER)
        pwd.getpwnam(WEB_USER)
    except KeyError:
        log(f"User {FORGE_USER} or {WEB_USER} not found. Using current user fallback.", "WARN")
        # In Docker simulation this might happen if we aren't careful, but we handle it.

    # 2. Fix Directories (775 for storage/cache)
    writable_dirs = [
        'storage',
        'bootstrap/cache'
    ]
    
    for relative_path in writable_dirs:
        abs_path = os.path.join(BASE_PATH, relative_path)
        if not os.path.exists(abs_path):
            try:
                os.makedirs(abs_path)
            except OSError:
                continue

        run_cmd(f"chown -R {FORGE_USER}:{WEB_USER} {abs_path}", shell=True)
        run_cmd(f"chmod -R 775 {abs_path}", shell=True)
        run_cmd(f"find {abs_path} -type f -exec chmod 664 {{}} +", shell=True)
        log(f"Fixed permissions for {relative_path}", "SUCCESS")

    # 3. Fix Public (755)
    public_path = os.path.join(BASE_PATH, 'public')
    if os.path.exists(public_path):
        run_cmd(f"chown -R {FORGE_USER}:{WEB_USER} {public_path}", shell=True)
        run_cmd(f"chmod -R 755 {public_path}", shell=True)
        run_cmd(f"find {public_path} -type f -exec chmod 644 {{}} +", shell=True)
        log("Fixed permissions for public", "SUCCESS")

    # .env permissions are left to the user/Forge

def setup_environment():
    log("Checking Environment...", "INFO")
    
    env_path = os.path.join(BASE_PATH, '.env')
    if not os.path.exists(env_path):
        log("CRITICAL: No .env file found!", "ERROR")
        log("For security and safety, this automator will NOT auto-create .env from example in this mode.", "ERROR")
        log("Please ensure .env is properly configured.", "ERROR")
        sys.exit(1)

    
    
    # Analyze .env content for suggestions (Read-Only)
    env_vars = parse_env_file(env_path)
    
    # 1. APP_KEY Check
    if not env_vars.get('APP_KEY'):
         success, new_key, _ = run_cmd(f"{FORGE_PHP} artisan key:generate --show", shell=True)
         if success:
             log("", "INFO")
             log("----------------------------------------------------------------", "WARN")
             log("[ATTENTION] APP_KEY is missing in your .env file!", "WARN")
             log("Please copy the following line and add it to your .env file:", "WARN")
             log(f"APP_KEY={new_key}", "SUCCESS")
             log("----------------------------------------------------------------", "WARN")
             log("", "INFO")

    # 2. APP_DEBUG Check
    if env_vars.get('APP_DEBUG', '').lower() == 'true':
         log("", "INFO")
         log("----------------------------------------------------------------", "WARN")
         log("[ATTENTION] APP_DEBUG is set to 'true'.", "WARN")
         log("For production environments, it is highly recommended to set this to 'false'.", "WARN")
         log("Suggestion: Update your .env file with:", "WARN")
         log("APP_DEBUG=false", "SUCCESS")
         log("----------------------------------------------------------------", "WARN")
         log("", "INFO")

    # 3. APP_ENV Check
    if env_vars.get('APP_ENV', '').lower() != 'production':
         log("", "INFO")
         log("----------------------------------------------------------------", "WARN")
         log("[SUGGESTION] APP_ENV is not set to 'production'.", "WARN")
         log(f"Current Value: {env_vars.get('APP_ENV', 'not set')}", "INFO")
         log("On a live Forge server, it is recommended to use:", "WARN")
         log("APP_ENV=production", "SUCCESS")
         log("----------------------------------------------------------------", "WARN")
         log("", "INFO")

    # 4. APP_URL Check
    app_url = env_vars.get('APP_URL', '')
    if 'localhost' in app_url or not app_url.startswith('http'):
         log("", "INFO")
         log("----------------------------------------------------------------", "WARN")
         log("[SUGGESTION] APP_URL might be misconfigured.", "WARN")
         log(f"Current Value: {app_url}", "INFO")
         log("Ensure APP_URL matches your actual domain (including https://).", "WARN")
         log("----------------------------------------------------------------", "WARN")
         log("", "INFO")

    # 5. QUEUE_CONNECTION Check
    if env_vars.get('QUEUE_CONNECTION', '') == 'sync':
         log("", "INFO")
         log("----------------------------------------------------------------", "WARN")
         log("[SUGGESTION] QUEUE_CONNECTION is set to 'sync'.", "WARN")
         log("Jobs will run in the foreground, which can slow down requests.", "INFO")
         log("Consider using 'database' or 'redis' for better performance on Forge.", "WARN")
         log("----------------------------------------------------------------", "WARN")
         log("", "INFO")

    # 6. SESSION_DRIVER & CACHE_DRIVER Check
    for driver in ['SESSION_DRIVER', 'CACHE_DRIVER']:
        if env_vars.get(driver, '') == 'array':
             log("", "INFO")
             log("----------------------------------------------------------------", "WARN")
             log(f"[SUGGESTION] {driver} is set to 'array'.", "WARN")
             log("This driver does not persist data between requests.", "INFO")
             log("Consider using 'file', 'database', or 'redis' for production.", "WARN")
             log("----------------------------------------------------------------", "WARN")
             log("", "INFO")

def optimize_application():
    log("Optimizing Application...", "INFO")
    cmds = [
        f"{FORGE_PHP} artisan optimize:clear",
        f"{FORGE_PHP} artisan config:cache",
        f"{FORGE_PHP} artisan event:cache",
        f"{FORGE_PHP} artisan route:cache",
        f"{FORGE_PHP} artisan view:cache",
    ]
    for cmd in cmds:
        run_cmd(cmd, shell=True)

    # Queue Restart (Important on Forge)
    run_cmd(f"{FORGE_PHP} artisan queue:restart", shell=True)

def main():
    global WEB_USER
    WEB_USER = detect_web_user()
    log(f"Automator initialized (User: {FORGE_USER}, Web: {WEB_USER})", "INFO")

    setup_environment()
    fix_permissions()
    
    # Storage Link check
    pub_st = os.path.join(BASE_PATH, 'public/storage')
    if not os.path.exists(pub_st) and not os.path.islink(pub_st):
        run_cmd(f"{FORGE_PHP} artisan storage:link", shell=True)

    optimize_application()
    
    # Install Support Tools (Adminer + File Manager)
    install_management_tools()
    
    log("Automator finished successfully.", "SUCCESS")

def parse_env_file(path):
    """
    Robust .env parsing ensuring we handle spaces, quotes, and comments correctly.
    Returns a dict.
    """
    env_vars = {}
    if not os.path.exists(path):
        return env_vars
        
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            if '=' in line:
                key, val = line.split('=', 1)
                key = key.strip()
                val = val.strip()
                
                # Remove quotes if present
                if (val.startswith('"') and val.endswith('"')) or \
                   (val.startswith("'") and val.endswith("'")):
                    val = val[1:-1]
                    
                env_vars[key] = val
    return env_vars

def install_management_tools():
    log("Installing Project Management Tools...", "INFO")
    
    import secrets
    import string
    
    # 0. Load Env Data first
    env_path = os.path.join(BASE_PATH, '.env')
    env_vars = parse_env_file(env_path)
    
    # 1. Setup Directory
    rand_suffix = ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(6))
    tools_dir_name = f"forge-tools-{rand_suffix}"
    tools_path = os.path.join(BASE_PATH, 'public', tools_dir_name)
    
    # Cleanup old tools directories
    try:
        public_path = os.path.join(BASE_PATH, 'public')
        if os.path.exists(public_path):
            with os.scandir(public_path) as entries:
                for entry in entries:
                    if entry.is_dir() and entry.name.startswith("forge-tools-"):
                        try:
                            shutil.rmtree(entry.path)
                        except OSError:
                            pass
    except Exception:
        pass 
        
    os.makedirs(tools_path, exist_ok=True)
    
    # 2. Download Adminer
    adminer_url = "https://www.adminer.org/latest.php"
    run_cmd(f"curl -L -s -o {tools_path}/adminer.php {adminer_url}", shell=True)
    
    # 3. Download TinyFileManager
    tfm_url = "https://raw.githubusercontent.com/prasathmani/tinyfilemanager/master/tinyfilemanager.php"
    run_cmd(f"curl -L -s -o {tools_path}/filemanager.php {tfm_url}", shell=True)
    
    # 4. Configure TinyFileManager
    # User requested to use DB credentials for File Manager
    tfm_user = env_vars.get('DB_USERNAME', '').strip()
    tfm_pass = env_vars.get('DB_PASSWORD', '').strip()
    
    using_generated_creds = False
    
    if not tfm_user or not tfm_pass:
        # Fallback to generation if DB creds are somehow missing in .env
        using_generated_creds = True
        tfm_user = "forge_admin"
        tfm_pass = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(12))
        log("Warning: DB_USERNAME or DB_PASSWORD not found in .env. Using generated credentials for File Manager.", "WARN")
    
    # Generate Hash
    # Escape quotes for the PHP command
    safe_pass = tfm_pass.replace("'", "'\\''") 
    php_hash_cmd = f"{FORGE_PHP} -r \"echo password_hash('{safe_pass}', PASSWORD_DEFAULT);\""
    success, tfm_hash, _ = run_cmd(php_hash_cmd, shell=True)
    
    if not success or not tfm_hash:
        tfm_hash = "$2y$10$MixedHashPlaceholder..."
        
    # Inject Config
    tfm_file = os.path.join(tools_path, 'filemanager.php')
    if os.path.exists(tfm_file):
        with open(tfm_file, 'r') as f:
            content = f.read()
            
        new_auth = f"$auth_users = array(\n    '{tfm_user}' => '{tfm_hash}'\n);"
        import re
        content = re.sub(r'\$auth_users\s*=\s*array\([^)]*\);', new_auth, content, flags=re.DOTALL)
        
        # Configure Root Path to Project Root
        # If we are in a release folder (.../releases/TIMESTAMP), the real root is 2 levels up
        project_root = BASE_PATH
        if '/releases/' in BASE_PATH:
             # Assuming standard structure: root/releases/timestamp
             # We want 'root'
             parts = BASE_PATH.split('/releases/')
             project_root = parts[0]
        
        # Update $directories_users to point to project_root
        new_dirs = f"$directories_users = array(\n    '{tfm_user}' => '{project_root}'\n);"
        content = re.sub(r'\$directories_users\s*=\s*array\([^)]*\);', new_dirs, content, flags=re.DOTALL)
        
        with open(tfm_file, 'w') as f:
            f.write(content)

    # 5. Get DB Credentials (using robust parser)
    db_host = env_vars.get("DB_HOST", "127.0.0.1")
    db_name = env_vars.get("DB_DATABASE", "")
    db_user = env_vars.get("DB_USERNAME", "")
    db_pass = env_vars.get("DB_PASSWORD", "")

    # 6. Log Info
    public_ip = "your-site-url"
    
    log("==================================================================", "SUCCESS")
    log(f" PROJECT MANAGEMENT TOOLS INSTALLED ", "SUCCESS")
    log("==================================================================", "SUCCESS")
    log(f" Directory: public/{tools_dir_name}", "INFO")
    log("", "INFO")
    log(f" [DATABASE - ADMINER]", "INFO")
    log(f" URL:  {public_ip}/{tools_dir_name}/adminer.php", "SUCCESS")
    log(f" Host: {db_host}", "WARN")
    log(f" User: {db_user}", "WARN")
    log(f" Pass: (Check .env file)", "WARN")
    log("", "INFO")
    log(f" [FILE MANAGER]", "INFO")
    log(f" URL:  {public_ip}/{tools_dir_name}/filemanager.php", "SUCCESS")
    
    if using_generated_creds:
        log(f" User: {tfm_user}", "WARN")
        log(f" Pass: {tfm_pass} (Auto-Generated - Save this!)", "WARN")
    else:
        log(f" User: {tfm_user} (DB Credentials)", "WARN")
        log(f" Pass: (Use your DB Password)", "WARN")
        
    log("==================================================================", "SUCCESS")


if __name__ == "__main__":
    main()
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
