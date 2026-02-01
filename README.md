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
