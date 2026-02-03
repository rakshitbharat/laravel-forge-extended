#!/bin/bash

################################################################################
# FastPanel Quick Fix Script
# 
# A comprehensive one-liner to fix common FastPanel installation and 
# configuration issues.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/fastpanel-fix.sh | bash
#
# Or with custom password:
#   curl -sL https://raw.githubusercontent.com/rakshitbharat/laravel-forge-extended/main/dist/fastpanel-fix.sh | FASTPANEL_PASSWORD='YourPassword123' bash
#
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
FASTPANEL_USER="${FASTPANEL_USER:-fastuser}"
FASTPANEL_PASSWORD="${FASTPANEL_PASSWORD:-}"
DEFAULT_PASSWORD="FastPanel2024#@"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_step() {
    echo -e "${BOLD}➜${NC} $1"
}

################################################################################
# Check if running as root
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo -e "  ${YELLOW}Please run: sudo bash${NC}"
        exit 1
    fi
    print_success "Running as root"
}

################################################################################
# Detect FastPanel Installation
################################################################################

detect_fastpanel() {
    print_step "Detecting FastPanel installation..."
    
    if systemctl is-active --quiet fastpanel2.service; then
        print_success "FastPanel is installed and running"
        return 0
    elif systemctl list-units --all | grep -q fastpanel2.service; then
        print_warning "FastPanel is installed but not running"
        return 0
    else
        print_error "FastPanel is not installed"
        return 1
    fi
}

################################################################################
# Check FastPanel Services
################################################################################

check_services() {
    print_step "Checking FastPanel services..."
    
    local services=(
        "fastpanel2.service"
        "fastpanel2-apps.service"
        "fastpanel2-nginx.service"
        "faststat.service"
    )
    
    local all_running=true
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            print_success "$service is running"
        else
            print_warning "$service is not running"
            all_running=false
        fi
    done
    
    if [ "$all_running" = false ]; then
        return 1
    fi
    return 0
}

################################################################################
# Restart FastPanel Services
################################################################################

restart_services() {
    print_step "Restarting FastPanel services..."
    
    local services=(
        "fastpanel2.service"
        "fastpanel2-apps.service"
        "fastpanel2-nginx.service"
        "faststat.service"
    )
    
    for service in "${services[@]}"; do
        if systemctl restart "$service" 2>/dev/null; then
            print_success "Restarted $service"
        else
            print_warning "Could not restart $service (may not exist)"
        fi
    done
    
    sleep 2
}

################################################################################
# Set FastPanel Password
################################################################################

set_password() {
    print_step "Setting FastPanel password..."
    
    local password="${FASTPANEL_PASSWORD:-$DEFAULT_PASSWORD}"
    
    # Check if mogwai command exists
    if ! command -v mogwai &> /dev/null; then
        print_warning "mogwai command not found, trying alternative path..."
        if [ -f "/usr/local/fastpanel2/fastpanel" ]; then
            alias mogwai="/usr/local/fastpanel2/fastpanel"
        else
            print_error "Cannot find FastPanel CLI"
            return 1
        fi
    fi
    
    # Change password
    if mogwai chpasswd --username="$FASTPANEL_USER" --password="$password" &>/dev/null; then
        print_success "Password set successfully"
        echo -e "  ${GREEN}Username:${NC} $FASTPANEL_USER"
        echo -e "  ${GREEN}Password:${NC} $password"
        return 0
    else
        print_error "Failed to set password"
        return 1
    fi
}

################################################################################
# Get Server IP
################################################################################

get_server_ip() {
    # Try multiple methods to get the server IP
    local ip=""
    
    # Method 1: Check eth0
    ip=$(ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n1)
    
    # Method 2: Check ens3 (common on some VPS)
    if [ -z "$ip" ]; then
        ip=$(ip addr show ens3 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n1)
    fi
    
    # Method 3: Use hostname -I
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    
    # Method 4: Use curl to get public IP
    if [ -z "$ip" ]; then
        ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
    fi
    
    echo "$ip"
}

################################################################################
# Generate Access URL
################################################################################

generate_access_url() {
    print_step "Generating access URL..."
    
    local ip=$(get_server_ip)
    
    if [ -z "$ip" ]; then
        print_error "Could not detect server IP"
        return 1
    fi
    
    # Try to generate auto-login token
    local login_url=""
    if command -v mogwai &> /dev/null; then
        login_url=$(mogwai usr 2>/dev/null | grep "https://" || echo "")
    fi
    
    if [ -n "$login_url" ]; then
        print_success "Auto-login URL generated"
        echo -e "\n${BOLD}${GREEN}Auto-Login URL (no password needed):${NC}"
        echo -e "${CYAN}$login_url${NC}\n"
    fi
    
    # Also show standard login
    echo -e "${BOLD}${GREEN}Standard Login:${NC}"
    echo -e "  ${CYAN}https://$ip:8888/${NC}"
    echo -e "  Username: ${YELLOW}$FASTPANEL_USER${NC}"
    echo -e "  Password: ${YELLOW}${FASTPANEL_PASSWORD:-$DEFAULT_PASSWORD}${NC}\n"
}

################################################################################
# Fix Permissions
################################################################################

fix_permissions() {
    print_step "Fixing FastPanel permissions..."
    
    local dirs=(
        "/usr/local/fastpanel2"
        "/var/www/fastuser"
        "/etc/nginx/fastpanel2-available"
        "/etc/apache2/fastpanel2-available"
    )
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            chmod -R 755 "$dir" 2>/dev/null && print_success "Fixed permissions for $dir" || print_warning "Could not fix $dir"
        fi
    done
}

################################################################################
# Check Firewall
################################################################################

check_firewall() {
    print_step "Checking firewall configuration..."
    
    local port=8888
    
    # Check if ufw is active
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        if ufw status | grep -q "$port"; then
            print_success "Port $port is allowed in UFW"
        else
            print_warning "Port $port is not allowed in UFW"
            echo -e "  ${YELLOW}Run: sudo ufw allow $port/tcp${NC}"
        fi
    fi
    
    # Check if iptables has rules
    if command -v iptables &> /dev/null; then
        if iptables -L -n | grep -q "$port"; then
            print_success "Port $port found in iptables"
        else
            print_info "No specific iptables rule for port $port (may use default accept)"
        fi
    fi
}

################################################################################
# System Information
################################################################################

show_system_info() {
    print_step "System Information..."
    
    echo -e "  ${BOLD}OS:${NC} $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo -e "  ${BOLD}Kernel:${NC} $(uname -r)"
    echo -e "  ${BOLD}IP Address:${NC} $(get_server_ip)"
    echo -e "  ${BOLD}Uptime:${NC} $(uptime -p 2>/dev/null || uptime)"
    
    # Disk usage
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    echo -e "  ${BOLD}Disk Usage:${NC} $disk_usage"
    
    # Memory usage
    local mem_usage=$(free -h | awk 'NR==2 {print $3 "/" $2}')
    echo -e "  ${BOLD}Memory Usage:${NC} $mem_usage"
}

################################################################################
# List Users
################################################################################

list_users() {
    print_step "FastPanel Users..."
    
    if command -v mogwai &> /dev/null; then
        echo ""
        mogwai users list 2>/dev/null || print_warning "Could not list users"
        echo ""
    fi
}

################################################################################
# Health Check
################################################################################

health_check() {
    print_step "Running health check..."
    
    local issues=0
    
    # Check if services are running
    if ! check_services; then
        ((issues++))
        print_warning "Some services are not running - attempting restart..."
        restart_services
    fi
    
    # Check disk space
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        ((issues++))
        print_warning "Disk usage is high: ${disk_usage}%"
    fi
    
    # Check memory
    local mem_usage=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
    if [ "$mem_usage" -gt 90 ]; then
        ((issues++))
        print_warning "Memory usage is high: ${mem_usage}%"
    fi
    
    if [ $issues -eq 0 ]; then
        print_success "All health checks passed"
    else
        print_warning "Found $issues potential issues"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header "🚀 FastPanel Quick Fix Script"
    
    # Check if running as root
    check_root
    
    # Show system info
    show_system_info
    echo ""
    
    # Detect FastPanel
    if ! detect_fastpanel; then
        print_error "FastPanel is not installed on this server"
        echo -e "\n${YELLOW}To install FastPanel, visit: https://fastpanel.direct/${NC}\n"
        exit 1
    fi
    
    # Run health check
    health_check
    echo ""
    
    # Fix permissions
    fix_permissions
    echo ""
    
    # Set password
    set_password
    echo ""
    
    # List users
    list_users
    
    # Check firewall
    check_firewall
    echo ""
    
    # Generate access URL
    generate_access_url
    
    # Final summary
    print_header "✅ FastPanel Quick Fix Complete!"
    
    print_success "FastPanel is configured and ready to use"
    print_info "You can regenerate the auto-login URL anytime with: ${BOLD}mogwai usr${NC}"
    
    echo -e "\n${CYAN}${BOLD}Quick Commands:${NC}"
    echo -e "  ${BOLD}List users:${NC}        mogwai users list"
    echo -e "  ${BOLD}Change password:${NC}   mogwai chpasswd --username=$FASTPANEL_USER --password='NewPassword'"
    echo -e "  ${BOLD}Restart services:${NC}  systemctl restart fastpanel2"
    echo -e "  ${BOLD}Check status:${NC}      systemctl status fastpanel2\n"
}

# Run main function
main "$@"
