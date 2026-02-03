# Laravel Forge Extended - Automator

This repository hosts a **self-healing deployment automator** for Laravel Forge. It completely takes over the deployment process, handling Git, Composer, Zero-Downtime Releases, and automatic Permission/Environment fixing.

## 🚀 Quick Usage (Forge)

In your Laravel Forge site dashboard, replace your entire **Deploy Script** with this single line:

```bash
cd /home/forge/{{<<<YOUR-WEBSITE-FOLDER>>>}}

git pull origin $FORGE_SITE_BRANCH

curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/automator.sh | bash
```

This single command will:
1.  Determine if you are running a Standard or Zero-Downtime deployment.
2.  Pull your latest code.
3.  Install dependencies (Composer & NPM).
4.  **Auto-Fix** permissions and storage links.
5.  **Display suggestions** for `.env` configuration issues (never modifies your `.env` file).
6.  Migrate your database and reload the server.

---

## 🌐 Cloudflare DNS Setup (Network Admin Tool)

A dedicated tool for Network Administrators to automatically configure Cloudflare DNS for Laravel applications.

### Features

- Reads `APP_URL` from `.env` automatically
- Detects server IP address
- Creates/updates DNS A record (domain → IP)
- Creates/updates DNS CNAME record (www → domain)
- Provides nameserver setup instructions
- Validates Cloudflare authentication and domain status

### Quick Start

```bash
# 1. Set your Cloudflare API token
export CF_API_TOKEN='your-cloudflare-api-token'

# 2. Run from your Laravel project directory
cd /home/forge/example.com
curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/cloudflare-dns-setup.sh | bash
```

📚 **[Full Documentation](docs/CLOUDFLARE_DNS_SETUP.md)** - Detailed setup guide, troubleshooting, and best practices.

---

## ⚡ FastPanel Quick Fix

A comprehensive one-liner to diagnose and fix common FastPanel installation and configuration issues. Perfect for newly installed FastPanel servers or troubleshooting existing installations.

### Features

- ✅ Detects FastPanel installation status
- ✅ Checks and restarts all FastPanel services
- ✅ Sets/resets admin password
- ✅ Fixes file permissions
- ✅ Generates auto-login URLs
- ✅ Performs system health checks
- ✅ Validates firewall configuration
- ✅ Lists all FastPanel users
- ✅ Displays system information and resource usage

### Quick Start

**Basic Usage (uses default password):**
```bash
curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/fastpanel-fix.sh | sudo bash
```

**With Custom Password:**
```bash
curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/fastpanel-fix.sh | FASTPANEL_PASSWORD='YourSecurePassword123#@' sudo bash
```

**With Custom Username:**
```bash
curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/fastpanel-fix.sh | FASTPANEL_USER='admin' FASTPANEL_PASSWORD='YourPassword' sudo bash
```

### What It Does

1. **System Check** - Verifies root access and displays system information
2. **Service Health** - Checks all FastPanel services (fastpanel2, nginx, apps, stats)
3. **Auto-Restart** - Restarts any stopped services automatically
4. **Permission Fix** - Corrects file permissions for FastPanel directories
5. **Password Reset** - Sets or updates the admin password
6. **Access URLs** - Generates both auto-login and standard login URLs
7. **Firewall Check** - Validates port 8888 is accessible
8. **User Management** - Lists all FastPanel users and their roles

### Default Credentials

If you don't specify a password, the script uses:
- **Username:** `fastuser`
- **Password:** `FastPanel2024#@`

### Common Use Cases

**After Fresh Installation:**
```bash
# Set your password and get access URL
curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/fastpanel-fix.sh | FASTPANEL_PASSWORD='MyPassword123#@' sudo bash
```

**Forgot Password:**
```bash
# Reset password and get new login URL
curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/fastpanel-fix.sh | FASTPANEL_PASSWORD='NewPassword123#@' sudo bash
```

**Services Not Running:**
```bash
# Diagnose and restart services
curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/fastpanel-fix.sh | sudo bash
```

### Manual Commands

After running the fix script, you can use these commands directly:

```bash
# Generate new auto-login URL
mogwai usr

# List all users
mogwai users list

# Change password manually
mogwai chpasswd --username=fastuser --password='NewPassword'

# Check service status
systemctl status fastpanel2

# Restart services
systemctl restart fastpanel2
```

---

## 🧹 Server Cleanup (Zero-Downtime Deployments)

Automatically clean up old releases, logs, cache, and temporary files across **all sites** on your Forge server.

### Quick Start

**Test First (Dry Run):**
```bash
curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/cleanup.sh | DRY_RUN=true bash
```

**Run Cleanup:**
```bash
curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/cleanup.sh | bash
```

### What Gets Cleaned

✅ **All Sites in `/home/forge/`:**
- Old zero-downtime deployment releases (keeps 3 most recent)
- Log files older than 30 days
- Cache files older than 7 days
- Session files older than 7 days

✅ **Server Cleanup (`/root`):**
- Old Let's Encrypt temporary directories
- Temporary files (`.tmp`, `.temp`, etc.)

✅ **Safety Features:**
- Never deletes the currently active release
- Dry run mode to preview changes
- Detailed logging of all deletions
- Shows total space freed

### Schedule with Cron (Runs at 12 AM Daily)

**Option 1: Laravel Forge UI**
1. Go to Server → **Scheduler** tab
2. Click **"New Scheduled Job"**
3. Set Command:
   ```bash
   curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/cleanup.sh | bash >> /home/forge/cleanup.log 2>&1
   ```
4. User: `root`
5. Frequency: Custom → `0 0 * * *`

**Option 2: Manual Cron**
```bash
sudo crontab -e
# Add this line:
0 0 * * * curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/cleanup.sh | bash >> /home/forge/cleanup.log 2>&1
```

### Configuration

Customize with environment variables:

```bash
# Keep only 2 releases
KEEP_RELEASES=2 curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/cleanup.sh | bash

# Keep logs for 60 days
KEEP_LOGS_DAYS=60 curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/cleanup.sh | bash
```

### View Logs

```bash
tail -100 /home/forge/cleanup.log
```

---

## 🛠️ Development & Contributing

This project uses a structured source format that is compiled into the single file used above.

### Project Structure

*   **`src/`**: The actual source code.
    *   `src/bash/bootstrap.sh`: The shell script that orchestrates deployment (Git, Composer, etc.).
    *   `src/python/automator.py`: The robust Python logic that handles "self-healing" fixes (Permissions, .env, etc.).
*   **`build.sh`**: A script that combines the files in `src/` into the final distribution file.
*   **`dist/`**: Contains the **generated** script ready for deployment.
    *   ⚠️ **Do not edit `dist/automator.sh` directly.** It will be overwritten by the build script.
*   **`docker/`**: Simulation environment for testing.

### How to Modify

1.  **Edit the source**: Make changes in `src/bash/bootstrap.sh` or `src/python/automator.py`.
2.  **Build**: Run the build script to regenerate the distribution file.
    ```bash
    ./build.sh
    ```
3.  **Commit**: Commit both the `src/` changes and the updated `dist/automator.sh`.

### Testing (Docker Simulation)

You can verify the script in a simulated Laravel Forge environment using Docker.

1.  Start the simulator:
    ```bash
    docker-compose up -d --build
    ```
2.  Run the automator inside the container:
    ```bash
    docker-compose exec forge-simulator bash /home/forge/dist/automator.sh
    ```
