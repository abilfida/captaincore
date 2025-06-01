#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "=== CaptainCore Server Setup Script ==="

# --- Helper Functions ---
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

# --- Phase 1: Initial Checks and Core Installation ---

# 1. Privilege Check
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root or with sudo."
    exit 1
fi
log_info "Privilege check passed (running as root or with sudo)."

# 2. Operating System Check
if ! grep -qi "ubuntu" /etc/os-release; then
    log_error "This script is intended for Ubuntu systems only."
    exit 1
fi
log_info "Operating system check passed (Ubuntu detected)."

# 3. Run existing install.sh for CaptainCore and dependencies
log_info "Starting CaptainCore core installation (will run install.sh)..."
if curl -s https://captaincore.io/install.sh | bash; then
    log_info "CaptainCore core installation script completed."
else
    log_error "CaptainCore core installation script failed."
    exit 1
fi

# --- Phase 1 Continued: CaptainCore Service Setup ---

# 4. Create systemd Service File for CaptainCore
SERVICE_USER=$(logname) # Get the username of the user who invoked sudo
SERVICE_GROUP=$(id -gn "$SERVICE_USER") # Get the primary group of that user

# Handle cases where sudo might not preserve logname or if run directly as root
if [ -z "$SERVICE_USER" ] || [ "$SERVICE_USER" == "root" ]; then
    SERVICE_USER="captaincore" # Default user if detection fails or is root
    SERVICE_GROUP="captaincore"
    if ! id "$SERVICE_USER" &>/dev/null; then
        log_info "Creating user '$SERVICE_USER' for CaptainCore service..."
        useradd -r -m -s /bin/false "$SERVICE_USER" || log_info "User '$SERVICE_USER' may already exist or could not be created. Continuing..."
    fi
fi

log_info "Configuring CaptainCore service to run as user '$SERVICE_USER' and group '$SERVICE_GROUP'."

CAPTAINCORE_SERVICE_FILE="/etc/systemd/system/captaincore.service"
log_info "Creating systemd service file at $CAPTAINCORE_SERVICE_FILE..."

cat << EOF > "$CAPTAINCORE_SERVICE_FILE"
[Unit]
Description=CaptainCore Application Server
Documentation=https://docs.captaincore.io
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
ExecStart=/usr/bin/captaincore server
Restart=always
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=captaincore

[Install]
WantedBy=multi-user.target
EOF

log_info "Systemd service file created."

# 5. Enable and Start the CaptainCore Service
log_info "Reloading systemd daemon..."
systemctl daemon-reload

log_info "Enabling CaptainCore service to start on boot..."
systemctl enable captaincore.service

log_info "Starting CaptainCore service..."
if systemctl start captaincore.service; then
    log_info "CaptainCore service started successfully."
    systemctl status captaincore.service --no-pager
else
    log_error "Failed to start CaptainCore service. Check logs with 'journalctl -u captaincore.service'."
    # Optionally, try to show last few log lines
    journalctl -u captaincore.service -n 20 --no-pager
    exit 1
fi

log_info "=== Phase 1 (Core Installation & Service Setup) Complete ==="
# End of Phase 1 for now. More to be added in subsequent phases.

# --- Phase 2: Caddy Installation and Configuration ---
log_info "=== Starting Phase 2: Caddy Installation and Configuration ==="

CADDY_INSTALLED=false
if command -v caddy &> /dev/null; then
    log_info "Caddy is already installed."
    CADDY_INSTALLED=true
else
    log_info "Caddy not found. Attempting to install Caddy..."
    # Install Caddy (official instructions for Debian/Ubuntu)
    # Reference: https://caddyserver.com/docs/install#debian-ubuntu-raspbian
    apt update && apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    if apt install -y caddy; then
        log_info "Caddy installed successfully."
        CADDY_INSTALLED=true
    else
        log_error "Failed to install Caddy. Please install Caddy manually and re-run this script or configure it manually."
        # exit 1 # Decide if this is a fatal error for the script
    fi
fi

if [ "$CADDY_INSTALLED" = true ]; then
    # Prompt for domain name
    DEFAULT_DOMAIN="captaincore.$(hostname -f 2>/dev/null || echo yourdomain.com)"
    read -r -p "Enter the public domain name for CaptainCore (e.g., captaincore.yourdomain.com, default: ${DEFAULT_DOMAIN}): " USER_DOMAIN
    if [ -z "$USER_DOMAIN" ]; then
        USER_DOMAIN="$DEFAULT_DOMAIN"
    fi
    log_info "Using domain: $USER_DOMAIN"

    # Generate Caddyfile
    CADDYFILE_PATH="/etc/caddy/Caddyfile"
    log_info "Generating Caddyfile at $CADDYFILE_PATH..."
    # Note: This will overwrite existing Caddyfile if not managed carefully.
    # For a more robust script, backup existing Caddyfile first.
    cat << EOF > "$CADDYFILE_PATH"
${USER_DOMAIN} {
    reverse_proxy localhost:8000
    # Optional: Enable automatic HTTPS and basic logging
    # tls your_email@example.com
    # log {
    # output file /var/log/caddy/access.log
    # }
}

# To serve other sites with Caddy, add their configurations here.
# example.com {
#   root * /var/www/example.com
#   file_server
# }
EOF
    log_info "Caddyfile generated."
    log_info "Important: If you use Caddy for other sites, you might need to merge this configuration manually."
    log_info "The generated Caddyfile looks like this:"
    cat "$CADDYFILE_PATH"
    echo # Newline for better readability

    # Reload Caddy service to apply changes
    log_info "Reloading Caddy service..."
    if systemctl reload caddy; then
        log_info "Caddy reloaded successfully."
    else
        log_error "Failed to reload Caddy. Starting/Restarting Caddy..."
        # Try to start or restart if reload failed (e.g., if it wasn't running)
        if systemctl is-active --quiet caddy; then
            if systemctl restart caddy; then
                log_info "Caddy restarted successfully."
            else
                log_error "Failed to restart Caddy. Please check Caddy's status and configuration: 'systemctl status caddy' and 'journalctl -u caddy'."
                log_error "Caddyfile is located at $CADDYFILE_PATH"
            fi
        else
            if systemctl start caddy; then
                log_info "Caddy started successfully."
            else
                log_error "Failed to start Caddy. Please check Caddy's status and configuration: 'systemctl status caddy' and 'journalctl -u caddy'."
                log_error "Caddyfile is located at $CADDYFILE_PATH"
            fi
        fi
    fi
else
    log_info "Skipping Caddy configuration as Caddy is not installed."
fi

log_info "=== Phase 2 (Caddy Installation and Configuration) Complete ==="
# End of Phase 2

# --- Phase 3: User Guidance and Final Steps ---
log_info "=== Starting Phase 3: User Guidance and Final Steps ==="

echo
log_info "---------------------------------------------------------------------"
log_info "CaptainCore Automated Setup: Next Steps & Manual Configuration"
log_info "---------------------------------------------------------------------"
echo

# 1. WordPress GUI Connection
log_info "MANUAL STEP 1: Connect WordPress GUI"
log_info "The CaptainCore server should now be running and accessible via Caddy."
log_info "If you configured a domain (e.g., ${USER_DOMAIN:-your_captaincore_domain.com}), it should be live."
log_info "To manage CaptainCore via a GUI:"
log_info " 1. Download the CaptainCore Manager plugin: https://github.com/CaptainCore/captaincore-manager/releases"
log_info " 2. Install and activate it on a WordPress site of your choice."
log_info " 3. Follow the plugin's prompts to connect to your CaptainCore instance."
log_info "    You'll likely need the server URL: http://localhost:8000 or https://${USER_DOMAIN:-your_captaincore_domain.com}"
echo

# 2. Cron Job Configuration
log_info "MANUAL STEP 2: Configure Cron Jobs"
log_info "For automated tasks like monitoring, backups, and updates, set up cron jobs."
log_info "Edit your crontab (usually for the '${SERVICE_USER:-captaincore}' user or root if appropriate):"
log_info "  sudo crontab -u ${SERVICE_USER:-captaincore} -e"
log_info "Or for the root user:"
log_info "  sudo crontab -e"
log_info ""
log_info "Add the following lines (adjust paths and schedules as needed):"
log_info "Ensure the PATH variable in your crontab includes /usr/bin and /usr/local/bin."
echo '# Example Crontab Entries for CaptainCore (adjust user/paths if needed)'
echo 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
echo ''
echo '# Monitor production sites every 10 minutes'
echo '*/10 * * * * captaincore monitor @production --fleet'
echo ''
echo '# Scan for errors on production sites nightly'
echo '45 18 * * * captaincore scan-errors @production --fleet'
echo ''
echo '# Run updates for production sites with "updates-on" tag weekly (Wednesday at 09:15)'
echo '15 09 * * 3 captaincore update @production.updates-on --fleet'
echo ''
echo '# Run updates for staging sites with "updates-on" tag quarterly (1st of the month at 00:15)'
echo '15 00 1 */3 * captaincore update @staging.updates-on --fleet'
echo ''
echo '# Generate backups for production sites nightly'
echo '03 00 * * * captaincore backup generate @production --fleet'
echo ''
echo '# Generate quicksaves for all sites nightly'
echo '01 00 * * * captaincore quicksave generate @all --fleet'
echo

# 3. Completion Message
log_info "---------------------------------------------------------------------"
log_info "CaptainCore automated setup script has finished."
log_info " - CaptainCore service should be running. Check with: systemctl status captaincore.service"
log_info " - Caddy service should be running and configured. Check with: systemctl status caddy.service"
log_info " - Review logs if needed: journalctl -u captaincore.service and journalctl -u caddy.service"
log_info "Please complete the manual steps above (WordPress GUI & Cron Jobs)."
log_info "Refer to SERVER_SETUP.md and https://docs.captaincore.io for more details."
log_info "=== Setup Script Complete ==="
echo
