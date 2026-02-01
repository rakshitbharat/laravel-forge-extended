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
#!/usr/bin/env python3

"""
Cloudflare DNS Automator
Handles automated DNS record creation for Laravel applications
"""

import os
import sys
import json
import subprocess
import urllib.request
import urllib.error
from typing import Dict, Optional, Tuple

# ==============================================================================
# Configuration
# ==============================================================================

BASE_PATH = os.getcwd()
ENV_FILE = os.path.join(BASE_PATH, '.env')

# Color codes for logging
COLORS = {
    'INFO': '\033[0;34m',
    'SUCCESS': '\033[0;32m',
    'WARN': '\033[1;33m',
    'ERROR': '\033[0;31m',
    'SECTION': '\033[1;36m',
    'RESET': '\033[0m'
}

# ==============================================================================
# Logging Functions
# ==============================================================================

def log(msg: str, level: str = "INFO"):
    """Print colored log message"""
    color = COLORS.get(level, COLORS['INFO'])
    reset = COLORS['RESET']
    print(f"{color}[{level}]{reset} {msg}")

def section(msg: str):
    """Print section header"""
    color = COLORS['SECTION']
    reset = COLORS['RESET']
    print(f"\n{color}{'='*60}{reset}")
    print(f"{color} {msg}{reset}")
    print(f"{color}{'='*60}{reset}\n")

# ==============================================================================
# Environment File Parser
# ==============================================================================

def parse_env_file(path: str) -> Dict[str, str]:
    """
    Parse .env file and return dictionary of key-value pairs
    Handles quotes, spaces, and comments
    """
    env_vars = {}
    
    if not os.path.exists(path):
        return env_vars
    
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            
            # Skip comments and empty lines
            if not line or line.startswith('#'):
                continue
            
            # Split on first = only
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

# ==============================================================================
# Domain Extraction
# ==============================================================================

def extract_domain(app_url: str) -> str:
    """Extract clean domain from APP_URL"""
    # Remove protocol
    domain = app_url.replace('http://', '').replace('https://', '')
    
    # Remove port
    if ':' in domain:
        domain = domain.split(':')[0]
    
    # Remove path
    if '/' in domain:
        domain = domain.split('/')[0]
    
    # Remove www (we'll add it back as CNAME)
    if domain.startswith('www.'):
        domain = domain[4:]
    
    return domain

# ==============================================================================
# Server IP Detection
# ==============================================================================

def get_server_ip() -> Optional[str]:
    """Detect server's public IP address"""
    methods = [
        'https://api.ipify.org',
        'https://icanhazip.com',
        'https://ifconfig.me/ip',
        'https://api.myip.com'
    ]
    
    for url in methods:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                ip = response.read().decode('utf-8').strip()
                # Validate IP format (basic check)
                parts = ip.split('.')
                if len(parts) == 4 and all(p.isdigit() and 0 <= int(p) <= 255 for p in parts):
                    return ip
        except:
            continue
    
    return None

# ==============================================================================
# Cloudflare API Client
# ==============================================================================

class CloudflareAPI:
    """Simple Cloudflare API client using urllib"""
    
    def __init__(self):
        self.api_token = os.environ.get('CF_API_TOKEN')
        self.api_email = os.environ.get('CF_API_EMAIL')
        self.api_key = os.environ.get('CF_API_KEY')
        self.base_url = 'https://api.cloudflare.com/client/v4'
        
    def _get_headers(self) -> Dict[str, str]:
        """Get authentication headers"""
        headers = {
            'Content-Type': 'application/json'
        }
        
        if self.api_token:
            headers['Authorization'] = f'Bearer {self.api_token}'
        elif self.api_email and self.api_key:
            headers['X-Auth-Email'] = self.api_email
            headers['X-Auth-Key'] = self.api_key
        else:
            raise ValueError("No API credentials found")
        
        return headers
    
    def _request(self, method: str, endpoint: str, data: Optional[Dict] = None) -> Dict:
        """Make HTTP request to Cloudflare API"""
        url = f"{self.base_url}/{endpoint}"
        headers = self._get_headers()
        
        req_data = json.dumps(data).encode('utf-8') if data else None
        request = urllib.request.Request(url, data=req_data, headers=headers, method=method)
        
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                result = json.loads(response.read().decode('utf-8'))
                if not result.get('success'):
                    errors = result.get('errors', [])
                    error_msg = errors[0].get('message', 'Unknown error') if errors else 'Unknown error'
                    raise Exception(f"API Error: {error_msg}")
                return result
        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8')
            try:
                error_data = json.loads(error_body)
                errors = error_data.get('errors', [])
                error_msg = errors[0].get('message', str(e)) if errors else str(e)
            except:
                error_msg = str(e)
            raise Exception(f"HTTP {e.code}: {error_msg}")
    
    def list_zones(self) -> list:
        """List all zones in account"""
        result = self._request('GET', 'zones')
        return result.get('result', [])
    
    def get_zone(self, domain: str) -> Optional[Dict]:
        """Get zone information for a domain"""
        result = self._request('GET', f'zones?name={domain}')
        zones = result.get('result', [])
        return zones[0] if zones else None
    
    def create_zone(self, domain: str) -> Dict:
        """Create a new zone (add domain to Cloudflare)"""
        data = {
            'name': domain,
            'jump_start': True  # Auto-scan existing DNS records
        }
        result = self._request('POST', 'zones', data)
        return result.get('result', {})
    
    def list_dns_records(self, zone_id: str) -> list:
        """List DNS records for a zone"""
        result = self._request('GET', f'zones/{zone_id}/dns_records')
        return result.get('result', [])
    
    def create_dns_record(self, zone_id: str, record_type: str, name: str, 
                         content: str, proxied: bool = True, ttl: int = 1) -> Dict:
        """Create a DNS record"""
        data = {
            'type': record_type,
            'name': name,
            'content': content,
            'proxied': proxied,
            'ttl': ttl
        }
        result = self._request('POST', f'zones/{zone_id}/dns_records', data)
        return result.get('result', {})
    
    def update_zone_settings(self, zone_id: str, settings: list) -> Dict:
        """Update multiple zone settings"""
        # Cloudflare allows updating multiple settings via PATCH /settings
        data = {"items": settings}
        result = self._request('PATCH', f'zones/{zone_id}/settings', data)
        return result.get('result', [])

    def update_single_setting(self, zone_id: str, setting_name: str, value: any) -> Dict:
        """Update a single zone setting"""
        data = {"value": value}
        result = self._request('PATCH', f'zones/{zone_id}/settings/{setting_name}', data)
        return result.get('result', {})

# ==============================================================================
# SSL Detection & Configuration
# ==============================================================================

def check_forge_ssl(domain: str) -> bool:
    """Check if SSL certificate exists on the server"""
    log("Checking for SSL certificate on server...", "INFO")
    
    # Try to make an HTTPS connection to the server directly (bypassing Cloudflare)
    # We need to get the origin IP first
    try:
        import socket
        # Get the actual server IP (not Cloudflare's)
        server_ip = get_server_ip()
        if not server_ip:
            return False
        
        # Try to connect to port 443
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(3)
        result = sock.connect_ex((server_ip, 443))
        sock.close()
        
        if result == 0:
            log("SSL certificate detected on server (Port 443 is open)", "SUCCESS")
            return True
        else:
            log("No SSL certificate detected on server (Port 443 closed)", "WARN")
            return False
    except Exception as e:
        log(f"Could not detect SSL status: {e}", "WARN")
        return False

def apply_performance_settings(cf: CloudflareAPI, zone_id: str, domain: str):
    """Apply 'Very Fast' performance profile with intelligent SSL configuration"""
    section("Optimizing for Speed & Security")
    
    # Check if server has SSL
    has_ssl = check_forge_ssl(domain)
    
    # Determine best SSL mode
    if has_ssl:
        ssl_mode = "full"  # Full (strict) requires valid cert
        log("Server has SSL certificate - Using 'Full' mode (Encrypted end-to-end)", "SUCCESS")
        print("")
        print("  ℹ️  Cloudflare will verify your server's SSL certificate.")
        print("  ℹ️  This provides maximum security and performance.")
        print("")
    else:
        ssl_mode = "flexible"
        log("No SSL detected on server - Using 'Flexible' mode", "WARN")
        print("")
        print("  ⚠️  WARNING: Connection between Cloudflare and your server is NOT encrypted!")
        print("  ⚠️  For production, you should install SSL on Laravel Forge.")
        print("")
        print("  To install SSL on Forge:")
        print("  1. Go to your Forge dashboard")
        print("  2. Select your site")
        print("  3. Click 'SSL' tab")
        print("  4. Click 'LetsEncrypt' (Free)")
        print("  5. Re-run this script to upgrade to 'Full' mode")
        print("")
    
    # List of settings to optimize
    optimizations = [
        ("ssl", ssl_mode, f"SSL Encryption Mode"),
        ("brotli", "on", "Brotli Compression"),
        ("always_use_https", "on", "Always Use HTTPS"),
        ("http3", "on", "HTTP/3 (QUIC)"),
        ("early_hints", "on", "Early Hints"),
        ("min_tls_version", "1.2", "Minimum TLS Version"),
        ("automatic_https_rewrites", "on", "Automatic HTTPS Rewrites"),
        ("opportunistic_encryption", "on", "Opportunistic Encryption"),
    ]
    
    log("Applying performance optimizations...", "INFO")
    print("")
    
    for setting, value, label in optimizations:
        try:
            cf.update_single_setting(zone_id, setting, value)
            log(f"  ✓ {label} → {value}", "SUCCESS")
        except Exception as e:
            # Some settings might not be available on free plan
            log(f"  ⊘ {label} (Not available on your plan)", "WARN")

    # Minification is a dict
    try:
        cf.update_single_setting(zone_id, "minify", {"css": "on", "html": "on", "js": "on"})
        log("  ✓ Auto Minification (JS/CSS/HTML)", "SUCCESS")
    except Exception as e:
        log(f"  ⊘ Minification (Not available on your plan)", "WARN")
    
    print("")
    
    # Additional recommendations
    if ssl_mode == "full":
        log("✅ Your site is now optimized for maximum speed and security!", "SUCCESS")
    else:
        log("⚠️  Your site is optimized for speed, but security can be improved with SSL", "WARN")

# ==============================================================================
# DNS Setup Functions
# ==============================================================================

def check_authentication() -> bool:
    """Check if Cloudflare API credentials are configured"""
    section("Checking Cloudflare Authentication")
    
    api_token = os.environ.get('CF_API_TOKEN')
    api_email = os.environ.get('CF_API_EMAIL')
    api_key = os.environ.get('CF_API_KEY')
    
    if api_token:
        log("Using CF_API_TOKEN for authentication", "INFO")
        return True
    elif api_email and api_key:
        log("Using CF_API_EMAIL and CF_API_KEY for authentication", "INFO")
        return True
    else:
        log("Cloudflare API credentials are NOT configured", "WARN")
        print("")
        print("Please set one of the following environment variables:")
        print("")
        print("  Option 1 (Recommended - API Token):")
        print("    export CF_API_TOKEN='your-api-token'")
        print("")
        print("  Option 2 (Legacy - Global API Key):")
        print("    export CF_API_EMAIL='your-email@example.com'")
        print("    export CF_API_KEY='your-global-api-key'")
        print("")
        print("Get your credentials from: https://dash.cloudflare.com/profile/api-tokens")
        print("")
        print("For production, add these to your shell profile (~/.bashrc or ~/.zshrc)")
        print("")
        return False

def check_domain_in_cloudflare(cf: CloudflareAPI, domain: str) -> Optional[Dict]:
    """Check if domain exists in Cloudflare account, create if not"""
    section("Checking Domain in Cloudflare")
    
    log(f"Checking if domain '{domain}' is in your Cloudflare account...", "INFO")
    
    try:
        zone = cf.get_zone(domain)
        if zone:
            log(f"Domain '{domain}' found in Cloudflare account", "SUCCESS")
            log(f"Zone ID: {zone['id']}", "INFO")
            log(f"Status: {zone['status']}", "INFO")
            return zone
        else:
            log(f"Domain '{domain}' not found. Adding to Cloudflare automatically...", "WARN")
            print("")
            
            # Automatically add domain to Cloudflare
            try:
                log(f"Creating zone for '{domain}'...", "INFO")
                new_zone = cf.create_zone(domain)
                
                if new_zone and new_zone.get('id'):
                    log(f"Domain '{domain}' successfully added to Cloudflare!", "SUCCESS")
                    log(f"Zone ID: {new_zone['id']}", "INFO")
                    log(f"Status: {new_zone['status']}", "INFO")
                    print("")
                    log("IMPORTANT: Update nameservers at your domain registrar", "WARN")
                    print("")
                    
                    # Display nameservers
                    nameservers = new_zone.get('name_servers', [])
                    if nameservers:
                        print("Update your domain's nameservers to:")
                        for ns in nameservers:
                            print(f"  • {ns}")
                        print("")
                        print("Go to your domain registrar (GoDaddy, Namecheap, etc.) and update the nameservers.")
                        print("DNS propagation can take up to 24-48 hours.")
                        print("")
                    
                    return new_zone
                else:
                    log("Failed to create zone. Please add manually.", "ERROR")
                    print("")
                    print("Manual steps:")
                    print("1. Go to: https://dash.cloudflare.com/")
                    print("2. Click 'Add a Site'")
                    print(f"3. Enter your domain: {domain}")
                    print("")
                    return None
                    
            except Exception as e:
                log(f"Error creating zone: {e}", "ERROR")
                print("")
                print("This might happen if:")
                print("- The domain is already registered to another Cloudflare account")
                print("- Your API token doesn't have 'Zone Create' permission")
                print("- The domain format is invalid")
                print("")
                print("Please add the domain manually at: https://dash.cloudflare.com/")
                print("")
                return None
                
    except Exception as e:
        log(f"Error checking domain: {e}", "ERROR")
        return None

def display_nameserver_info(zone: Dict):
    """Display nameserver information"""
    nameservers = zone.get('name_servers', [])
    
    if nameservers:
        print("")
        log("IMPORTANT: Update DNS Nameservers at Your Domain Registrar", "WARN")
        print("")
        print("Go to your domain registrar (GoDaddy, Namecheap, etc.) and update the nameservers to:")
        print("")
        for ns in nameservers:
            print(f"  • {ns}")
        print("")
        print("This is required for Cloudflare to manage your DNS.")
        print("DNS propagation can take up to 24-48 hours, but usually completes within a few hours.")
        print("")
    else:
        log("Could not retrieve nameservers. Please check manually at:", "WARN")
        print("https://dash.cloudflare.com/")

def create_or_update_a_record(cf: CloudflareAPI, zone_id: str, domain: str, ip: str) -> bool:
    """Create or update A record"""
    section("Managing DNS A Record")
    
    log(f"Setting up A record for '{domain}' pointing to '{ip}'...", "INFO")
    
    try:
        # Get existing DNS records
        records = cf.list_dns_records(zone_id)
        
        # Find existing A record for root domain
        existing_record = None
        for record in records:
            if record['type'] == 'A' and record['name'] == domain:
                existing_record = record
                break
        
        if existing_record:
            log(f"Found existing A record: {existing_record['name']} → {existing_record['content']}", "INFO")
            
            if existing_record['content'] == ip:
                log("A record already points to the correct IP. No changes needed.", "SUCCESS")
                return True
            
            # Update existing record
            log(f"Updating A record to point to {ip}...", "INFO")
            cf.update_dns_record(
                zone_id,
                existing_record['id'],
                'A',
                domain,
                ip,
                proxied=True
            )
            log(f"A record updated successfully: {domain} → {ip} (Proxied)", "SUCCESS")
        else:
            # Create new A record
            log(f"Creating new A record...", "INFO")
            cf.create_dns_record(
                zone_id,
                'A',
                domain,
                ip,
                proxied=True
            )
            log(f"A record created successfully: {domain} → {ip} (Proxied)", "SUCCESS")
        
        return True
        
    except Exception as e:
        log(f"Failed to create/update A record: {e}", "ERROR")
        print("You can create it manually at: https://dash.cloudflare.com/")
        return False

def create_or_update_cname_record(cf: CloudflareAPI, zone_id: str, domain: str) -> bool:
    """Create or update CNAME record for www"""
    section("Managing DNS CNAME Record")
    
    www_domain = f"www.{domain}"
    log(f"Setting up CNAME record for '{www_domain}' pointing to '{domain}'...", "INFO")
    
    try:
        # Get existing DNS records
        records = cf.list_dns_records(zone_id)
        
        # Find existing CNAME record for www
        existing_record = None
        for record in records:
            if record['type'] == 'CNAME' and record['name'] == www_domain:
                existing_record = record
                break
        
        if existing_record:
            log(f"Found existing CNAME record: {existing_record['name']} → {existing_record['content']}", "INFO")
            
            if existing_record['content'] == domain:
                log("CNAME record already points to the correct domain. No changes needed.", "SUCCESS")
                return True
            
            # Update existing record
            log(f"Updating CNAME record to point to {domain}...", "INFO")
            cf.update_dns_record(
                zone_id,
                existing_record['id'],
                'CNAME',
                www_domain,
                domain,
                proxied=True
            )
            log(f"CNAME record updated successfully: {www_domain} → {domain} (Proxied)", "SUCCESS")
        else:
            # Create new CNAME record
            log(f"Creating new CNAME record...", "INFO")
            cf.create_dns_record(
                zone_id,
                'CNAME',
                www_domain,
                domain,
                proxied=True
            )
            log(f"CNAME record created successfully: {www_domain} → {domain} (Proxied)", "SUCCESS")
        
        return True
        
    except Exception as e:
        log(f"Failed to create/update CNAME record: {e}", "ERROR")
        print("You can create it manually at: https://dash.cloudflare.com/")
        return False

# ==============================================================================
# Main Execution
# ==============================================================================

def main():
    """Main execution function"""
    print("🌐 Starting Cloudflare DNS Automator...")
    print("")
    
    # Check .env file
    if not os.path.exists(ENV_FILE):
        log(".env file not found!", "ERROR")
        log(f"Expected location: {ENV_FILE}", "ERROR")
        log("Please ensure you're running this script from your Laravel project directory.", "ERROR")
        sys.exit(1)
    
    # Parse .env
    env_vars = parse_env_file(ENV_FILE)
    
    # Get APP_URL
    app_url = env_vars.get('APP_URL', '')
    
    if not app_url:
        log("APP_URL is not set in .env file", "ERROR")
        log("Please set APP_URL in your .env file (e.g., APP_URL=https://example.com)", "ERROR")
        sys.exit(1)
    
    log(f"APP_URL found: {app_url}", "INFO")
    
    # Extract domain
    domain = extract_domain(app_url)
    
    if not domain:
        log(f"Could not extract domain from APP_URL: {app_url}", "ERROR")
        sys.exit(1)
    
    log(f"Domain extracted: {domain}", "SUCCESS")
    
    # Get server IP
    server_ip = get_server_ip()
    
    if not server_ip:
        log("Could not auto-detect server IP address", "WARN")
        server_ip = input("Please enter server IP address: ").strip()
        
        if not server_ip:
            log("No IP address provided. Exiting.", "ERROR")
            sys.exit(1)
    
    log(f"Server IP: {server_ip}", "SUCCESS")
    
    # Check authentication
    if not check_authentication():
        log("Cloudflare API credentials are not configured. Please set them first.", "ERROR")
        sys.exit(1)
    
    # Initialize Cloudflare API
    try:
        cf = CloudflareAPI()
    except ValueError as e:
        log(str(e), "ERROR")
        sys.exit(1)
    
    # Check if domain exists in Cloudflare
    zone = check_domain_in_cloudflare(cf, domain)
    
    if not zone:
        log("Domain is not in your Cloudflare account. Please add it first.", "ERROR")
        sys.exit(1)
    
    zone_id = zone['id']
    
    # Display nameserver information
    display_nameserver_info(zone)
    
    # Create/update A record
    a_record_success = create_or_update_a_record(cf, zone_id, domain, server_ip)
    
    # Create/update CNAME record
    cname_record_success = create_or_update_cname_record(cf, zone_id, domain)
    
    # Apply Performance Optimization
    apply_performance_settings(cf, zone_id, domain)
    
    # Final summary
    section("Setup Complete!")
    
    print("Summary of DNS records:")
    print("")
    if a_record_success:
        print(f"  ✓ A Record:     {domain} → {server_ip} (Proxied)")
    else:
        print(f"  ✗ A Record:     Failed to create/update")
    
    if cname_record_success:
        print(f"  ✓ CNAME Record: www.{domain} → {domain} (Proxied)")
    else:
        print(f"  ✗ CNAME Record: Failed to create/update")
    
    print("")
    print("Next steps:")
    print("")
    print("1. Ensure nameservers are updated at your domain registrar")
    print("2. Wait for DNS propagation (usually 5-30 minutes)")
    print("3. Update Laravel TrustProxies middleware:")
    print("   - Laravel 11: bootstrap/app.php → $middleware->trustProxies(at: '*')")
    print("   - Laravel 10: app/Http/Middleware/TrustProxies.php → protected $proxies = '*'")
    print(f"4. Test your domain: https://{domain}")
    print("")
    print("Cloudflare Dashboard: https://dash.cloudflare.com/")
    print("")
    log("All done! 🎉", "SUCCESS")

if __name__ == "__main__":
    main()
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
