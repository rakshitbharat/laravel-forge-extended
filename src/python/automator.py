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
