#!/bin/bash

# Laravel Forge Server Cleanup Script
# Cleans ALL sites + server temporary files
# Safe: Keeps 3 most recent releases, never deletes active release

set -e

# Configuration
KEEP_RELEASES=3
KEEP_LOGS_DAYS=30
KEEP_CACHE_DAYS=7
DRY_RUN="${DRY_RUN:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Track total freed space
TOTAL_FREED=0

safe_delete() {
    local target="$1"
    local desc="$2"
    
    if [ "$DRY_RUN" = "true" ]; then
        warn "[DRY RUN] Would delete: $desc"
        return 0
    fi
    
    if [ -e "$target" ]; then
        local size=$(du -sb "$target" 2>/dev/null | cut -f1 || echo "0")
        rm -rf "$target"
        TOTAL_FREED=$((TOTAL_FREED + size))
        success "Deleted: $desc"
        return 0
    fi
    return 1
}

bytes_to_human() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes}B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Laravel Forge Server Cleanup                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$DRY_RUN" = "true" ]; then
    warn "DRY RUN MODE - No files will be deleted"
    echo ""
fi

log "Configuration:"
log "  Keep Releases: $KEEP_RELEASES"
log "  Keep Logs: $KEEP_LOGS_DAYS days"
log "  Keep Cache: $KEEP_CACHE_DAYS days"
echo ""

# ============================================================================
# 1. Clean /root temporary files
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "1. Cleaning /root temporary files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Clean old Let's Encrypt temp directories
letsencrypt_count=0
for dir in /root/letsencrypt*; do
    if [ -d "$dir" ]; then
        safe_delete "$dir" "Let's Encrypt temp: $(basename "$dir")"
        letsencrypt_count=$((letsencrypt_count + 1))
    fi
done

if [ $letsencrypt_count -gt 0 ]; then
    success "Cleaned $letsencrypt_count Let's Encrypt temp directories"
else
    log "No Let's Encrypt temp directories found"
fi

# Clean other temp files in /root
for pattern in "*.tmp" "*.temp" ".cloudflare_automator.py"; do
    for file in /root/$pattern; do
        if [ -f "$file" ]; then
            safe_delete "$file" "Temp file: $(basename "$file")"
        fi
    done
done

echo ""

# ============================================================================
# 2. Clean all Laravel sites
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "2. Cleaning all Laravel sites"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for site_dir in /home/forge/*/; do
    site_name=$(basename "$site_dir")
    
    # Skip hidden directories
    case "$site_name" in
        .*) continue ;;
    esac
    
    echo ""
    log "Processing: $site_name"
    
    # ========================================================================
    # Zero-Downtime Deployment Cleanup
    # ========================================================================
    if [ -d "$site_dir/releases" ]; then
        log "  Type: Zero-Downtime Deployment"
        
        # Get current release
        current_release=""
        if [ -L "$site_dir/current" ]; then
            current_release=$(readlink "$site_dir/current")
        fi
        
        # Count releases
        release_count=$(ls -1 "$site_dir/releases" 2>/dev/null | wc -l)
        log "  Total releases: $release_count"
        
        if [ $release_count -gt $KEEP_RELEASES ]; then
            # Get releases to delete (all except newest N)
            releases_to_delete=$(ls -t "$site_dir/releases" | tail -n +$((KEEP_RELEASES + 1)))
            
            delete_count=0
            while IFS= read -r release; do
                [ -z "$release" ] && continue
                
                release_path="$site_dir/releases/$release"
                
                # Safety: never delete current release
                if [ "$release_path" = "$current_release" ]; then
                    warn "  Skipping active release: $release"
                    continue
                fi
                
                safe_delete "$release_path" "  Release: $release"
                delete_count=$((delete_count + 1))
            done <<< "$releases_to_delete"
            
            if [ $delete_count -gt 0 ]; then
                success "  Cleaned $delete_count old releases"
            fi
        else
            log "  Only $release_count releases (keeping all)"
        fi
        
        # Clean shared storage
        if [ -d "$site_dir/shared/storage" ]; then
            # Clean old logs
            if [ -d "$site_dir/shared/storage/logs" ]; then
                old_logs=$(find "$site_dir/shared/storage/logs" -name "*.log" -mtime +$KEEP_LOGS_DAYS 2>/dev/null)
                log_count=0
                while IFS= read -r logfile; do
                    [ -z "$logfile" ] && continue
                    safe_delete "$logfile" "  Log: $(basename "$logfile")"
                    log_count=$((log_count + 1))
                done <<< "$old_logs"
                [ $log_count -gt 0 ] && success "  Cleaned $log_count old log files"
            fi
            
            # Clean old cache
            if [ -d "$site_dir/shared/storage/framework/cache" ]; then
                old_cache=$(find "$site_dir/shared/storage/framework/cache" -type f -mtime +$KEEP_CACHE_DAYS 2>/dev/null)
                cache_count=0
                while IFS= read -r cachefile; do
                    [ -z "$cachefile" ] && continue
                    safe_delete "$cachefile" "  Cache file"
                    cache_count=$((cache_count + 1))
                done <<< "$old_cache"
                [ $cache_count -gt 0 ] && success "  Cleaned $cache_count cache files"
            fi
            
            # Clean old sessions
            if [ -d "$site_dir/shared/storage/framework/sessions" ]; then
                old_sessions=$(find "$site_dir/shared/storage/framework/sessions" -type f -mtime +7 2>/dev/null)
                session_count=0
                while IFS= read -r sessionfile; do
                    [ -z "$sessionfile" ] && continue
                    safe_delete "$sessionfile" "  Session file"
                    session_count=$((session_count + 1))
                done <<< "$old_sessions"
                [ $session_count -gt 0 ] && success "  Cleaned $session_count session files"
            fi
        fi
        
    # ========================================================================
    # Standard Deployment Cleanup
    # ========================================================================
    elif [ -d "$site_dir/storage" ]; then
        log "  Type: Standard Deployment"
        
        # Clean old logs
        if [ -d "$site_dir/storage/logs" ]; then
            old_logs=$(find "$site_dir/storage/logs" -name "*.log" -mtime +$KEEP_LOGS_DAYS 2>/dev/null)
            log_count=0
            while IFS= read -r logfile; do
                [ -z "$logfile" ] && continue
                safe_delete "$logfile" "  Log: $(basename "$logfile")"
                log_count=$((log_count + 1))
            done <<< "$old_logs"
            [ $log_count -gt 0 ] && success "  Cleaned $log_count old log files"
        fi
        
        # Clean old cache
        if [ -d "$site_dir/storage/framework/cache" ]; then
            old_cache=$(find "$site_dir/storage/framework/cache" -type f -mtime +$KEEP_CACHE_DAYS 2>/dev/null)
            cache_count=0
            while IFS= read -r cachefile; do
                [ -z "$cachefile" ] && continue
                safe_delete "$cachefile" "  Cache file"
                cache_count=$((cache_count + 1))
            done <<< "$old_cache"
            [ $cache_count -gt 0 ] && success "  Cleaned $cache_count cache files"
        fi
        
        # Clean old sessions
        if [ -d "$site_dir/storage/framework/sessions" ]; then
            old_sessions=$(find "$site_dir/storage/framework/sessions" -type f -mtime +7 2>/dev/null)
            session_count=0
            while IFS= read -r sessionfile; do
                [ -z "$sessionfile" ] && continue
                safe_delete "$sessionfile" "  Session file"
                session_count=$((session_count + 1))
            done <<< "$old_sessions"
            [ $session_count -gt 0 ] && success "  Cleaned $session_count session files"
        fi
    else
        log "  Type: Not a Laravel site (skipping)"
    fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Cleanup Summary                                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$DRY_RUN" = "true" ]; then
    warn "DRY RUN - No files were actually deleted"
else
    freed_human=$(bytes_to_human $TOTAL_FREED)
    success "Total space freed: $freed_human"
fi

echo ""
success "✅ Cleanup completed successfully!"
echo ""
