#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Helper Functions ---
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_warning() {
    echo "[WARN] $1" >&2
}

# --- Configuration ---
MIN_GO_VERSION_MAJOR=1
MIN_GO_VERSION_MINOR=18
GO_INSTALL_DIR="/usr/local/go"
GO_PROFILE_SCRIPT="/etc/profile.d/golang.sh" # Changed from goroot.sh to golang.sh for clarity

# --- Phase 1: System Checks and Go Installation ---

log_info "=== CaptainCore Dependency Installer ==="
log_info "Phase 1: System Checks and Go Installation"

# 1. Privilege Check
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root or with sudo."
    exit 1
fi
log_info "Privilege check passed."

# 2. Operating System Check (Ubuntu)
if ! grep -qi "ubuntu" /etc/os-release; then
    log_error "This script is primarily intended for Ubuntu systems."
    # Consider adding a Y/N prompt to continue for other Debian-based systems
    # For now, exiting.
    exit 1
fi
log_info "Operating system check passed (Ubuntu detected)."

# 3. Go Installation
GO_VERSION_OK=false
if command -v go &> /dev/null; then
    log_info "Go is already installed."
    # Check version
    CURRENT_GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    CURRENT_GO_MAJOR=$(echo "$CURRENT_GO_VERSION" | cut -d. -f1)
    CURRENT_GO_MINOR=$(echo "$CURRENT_GO_VERSION" | cut -d. -f2)

    log_info "Detected Go version: $CURRENT_GO_VERSION"

    if [ "$CURRENT_GO_MAJOR" -gt "$MIN_GO_VERSION_MAJOR" ] ||        ( [ "$CURRENT_GO_MAJOR" -eq "$MIN_GO_VERSION_MAJOR" ] &&          [ "$CURRENT_GO_MINOR" -ge "$MIN_GO_VERSION_MINOR" ] ); then
        log_info "Installed Go version ($CURRENT_GO_VERSION) meets requirements (>= $MIN_GO_VERSION_MAJOR.$MIN_GO_VERSION_MINOR)."
        GO_VERSION_OK=true
    else
        log_info "Installed Go version ($CURRENT_GO_VERSION) is older than required (>= $MIN_GO_VERSION_MAJOR.$MIN_GO_VERSION_MINOR)."
        # Consider removing old version or prompting user
        log_info "Proceeding to install a newer version of Go."
        # Best practice would be to remove or rename the old version path if it's in /usr/local/go
        if [ -d "$GO_INSTALL_DIR" ]; then
            log_info "An existing Go installation was found at $GO_INSTALL_DIR. It might be overwritten or conflict."
            # read -r -p "Rename $GO_INSTALL_DIR to $GO_INSTALL_DIR.old and proceed? (y/N) " confirm_rename
            # if [[ "$confirm_rename" =~ ^[yY](es)?$ ]]; then
            #   mv "$GO_INSTALL_DIR" "$GO_INSTALL_DIR.old_$(date +%s)"
            # else
            #   log_error "Aborting due to existing Go installation at $GO_INSTALL_DIR."
            #   exit 1
            # fi
            # For now, we'll assume if version is too old, we will overwrite /usr/local/go if it exists.
        fi
    fi
fi

if [ "$GO_VERSION_OK" = false ]; then
    log_info "Installing Go (version >= $MIN_GO_VERSION_MAJOR.$MIN_GO_VERSION_MINOR)..."
    # Fetch the latest Go version dynamically if possible, or use a fixed known good version
    # For simplicity, let's use a recent known version. Update this as needed.
    # Example: GO_LATEST_VERSION="1.21.5"
    # To fetch latest:
    # GO_LATEST_VERSION_URL="https://go.dev/VERSION?m=text"
    # GO_LATEST_VERSION_FULL=$(curl -s "$GO_LATEST_VERSION_URL" | head -n 1) # e.g., go1.21.5
    # GO_LATEST_VERSION=$(echo "$GO_LATEST_VERSION_FULL" | sed 's/go//')

    # Using a fixed recent version for robustness in this script for now
    DESIRED_GO_VERSION="1.21.6" # Check https://go.dev/dl/ for latest stable
    ARCH=$(uname -m)
    GO_ARCH="amd64" # Default
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        GO_ARCH="arm64"
    elif [ "$ARCH" = "x86_64" ]; then
        GO_ARCH="amd64"
    else
        log_error "Unsupported architecture: $ARCH. Cannot automatically install Go."
        exit 1
    fi

    GO_TARBALL="go${DESIRED_GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    GO_DOWNLOAD_URL="https://dl.google.com/go/${GO_TARBALL}"

    log_info "Downloading Go $DESIRED_GO_VERSION for $GO_ARCH from $GO_DOWNLOAD_URL..."
    # Clean up previous downloads if any
    rm -f "/tmp/${GO_TARBALL}"
    if curl -Lo "/tmp/${GO_TARBALL}" "$GO_DOWNLOAD_URL"; then
        log_info "Go tarball downloaded successfully."
    else
        log_error "Failed to download Go tarball."
        exit 1
    fi

    log_info "Extracting Go tarball to $GO_INSTALL_DIR..."
    # Remove old installation if exists and we decided to overwrite
    if [ -d "$GO_INSTALL_DIR" ]; then
        rm -rf "$GO_INSTALL_DIR"
        log_info "Removed existing directory: $GO_INSTALL_DIR"
    fi
    tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
    log_info "Go extracted to $GO_INSTALL_DIR."

    # Clean up downloaded tarball
    rm -f "/tmp/${GO_TARBALL}"

    log_info "Go $DESIRED_GO_VERSION installed successfully."
fi

# 4. Setup Go PATH environment variable
if [ ! -f "$GO_PROFILE_SCRIPT" ] || ! grep -q "$GO_INSTALL_DIR/bin" "$GO_PROFILE_SCRIPT"; then
    log_info "Setting up Go PATH in $GO_PROFILE_SCRIPT..."
    # Ensure the directory exists
    mkdir -p "$(dirname "$GO_PROFILE_SCRIPT")"
    # Create or update the profile script
    echo "export PATH=\$PATH:${GO_INSTALL_DIR}/bin" > "$GO_PROFILE_SCRIPT"
    echo "export GOPATH=\$HOME/go" >> "$GO_PROFILE_SCRIPT" # Optional: common Go practice
    echo "export PATH=\$PATH:\$GOPATH/bin" >> "$GO_PROFILE_SCRIPT" # Optional
    chmod +x "$GO_PROFILE_SCRIPT"
    log_info "Go PATH setup complete. Please source $GO_PROFILE_SCRIPT or log out/in to apply."
    log_info "For current session, exporting PATH (sudo context might not affect calling user's shell directly):"
    export PATH="$PATH:${GO_INSTALL_DIR}/bin"
else
    log_info "Go PATH already configured in $GO_PROFILE_SCRIPT."
fi

# Test if 'go version' can be run now (might require new shell or sourcing profile)
# Attempt to source it for the current script execution if possible, though this won't affect the parent shell.
# shellcheck source=/dev/null
source "$GO_PROFILE_SCRIPT" || log_info "Could not source $GO_PROFILE_SCRIPT for current script session."

if command -v go &> /dev/null; then
    log_info "Go command is available. Version: $(go version | awk '{print $3}')"
else
    log_error "Go command not found in PATH after installation. Manual PATH setup might be required."
    log_error "Try running: source $GO_PROFILE_SCRIPT"
    # This is a critical failure for subsequent steps if Go is needed for compilation.
fi

log_info "=== Phase 1 (System Checks and Go Installation) Complete ==="
echo

# --- Phase 2: WP-CLI Installation ---
log_info "=== Starting Phase 2: WP-CLI Installation ==="

WPCLI_INSTALL_PATH="/usr/local/bin/wp"

if command -v wp &> /dev/null; then
    # Check if it's the actual WP-CLI and not some other 'wp' alias or script
    # A simple check could be 'wp --info' which should return 0
    if wp --info &> /dev/null; then
        log_info "WP-CLI is already installed at $(command -v wp)."
        log_info "WP-CLI version: $(wp cli version --quiet)" # Using --quiet to avoid potential non-zero exit on some setups if only version is needed
    else
        log_info "A command 'wp' exists but doesn't seem to be WP-CLI. Proceeding with installation."
        install_wp_cli=true
    fi
else
    install_wp_cli=true
fi

if [ "$install_wp_cli" = true ]; then
    log_info "Installing WP-CLI..."
    WPCLI_PHAR_URL="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"

    log_info "Downloading wp-cli.phar from $WPCLI_PHAR_URL..."
    if curl -Lo "/tmp/wp-cli.phar" "$WPCLI_PHAR_URL"; then
        log_info "wp-cli.phar downloaded successfully."
    else
        log_error "Failed to download wp-cli.phar."
        # Decide if this is fatal. WP-CLI is a strong dependency for CaptainCore.
        exit 1
    fi

    log_info "Making wp-cli.phar executable..."
    chmod +x "/tmp/wp-cli.phar"

    log_info "Moving wp-cli.phar to $WPCLI_INSTALL_PATH..."
    # Check if the destination directory exists, though /usr/local/bin should.
    if [ ! -d "$(dirname "$WPCLI_INSTALL_PATH")" ]; then
        log_error "Installation directory $(dirname "$WPCLI_INSTALL_PATH") does not exist. This is unexpected."
        exit 1
    fi
    # Remove if it exists and is a symlink or a different file, to avoid issues.
    if [ -e "$WPCLI_INSTALL_PATH" ]; then
        log_info "Removing existing file/symlink at $WPCLI_INSTALL_PATH."
        rm -f "$WPCLI_INSTALL_PATH"
    fi
    if mv "/tmp/wp-cli.phar" "$WPCLI_INSTALL_PATH"; then
        log_info "WP-CLI installed successfully to $WPCLI_INSTALL_PATH."
        log_info "WP-CLI version: $(wp cli version --quiet || echo 'unknown')"
    else
        log_error "Failed to move wp-cli.phar to $WPCLI_INSTALL_PATH."
        log_error "Please check permissions for $WPCLI_INSTALL_PATH."
        exit 1
    fi
else
    # This branch is taken if WP-CLI was already found and verified.
    : # Do nothing, already logged
fi

log_info "=== Phase 2 (WP-CLI Installation) Complete ==="
echo

# --- Phase 3: Git Installation and CaptainCore Binary Installation ---
log_info "=== Starting Phase 3: Git and CaptainCore Binary Installation ==="

# 1. Install Git (useful utility, and fallback for source compilation if ever needed)
if command -v git &> /dev/null; then
    log_info "Git is already installed. Version: $(git --version)"
else
    log_info "Installing Git..."
    if apt-get update && apt-get install -y git; then
        log_info "Git installed successfully. Version: $(git --version)"
    else
        log_error "Failed to install Git. This might affect some functionalities if source code operations are ever needed."
        # Not exiting, as core functionality might still work if binary download succeeds.
    fi
fi

# 2. CaptainCore Binary Installation (from GitHub Releases)
CAPTAINCORE_INSTALL_PATH="/usr/local/bin/captaincore"
# These should be updated if the repository name or release asset naming changes.
CAPTAINCORE_REPO="CaptainCore/captaincore" # Assuming this is the GitHub repo path
# To get the latest release tag:
# LATEST_TAG=$(curl -s "https://api.github.com/repos/${CAPTAINCORE_REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*//')
# For now, using a placeholder or assuming 'latest'. If a specific version is needed, set it here.
# If using 'latest', the download URL might redirect.
# The actual asset name might include the version and OS/arch.
# e.g., captaincore_0.5.0_linux_amd64

# Let's try to get the latest release tag
LATEST_TAG=""
log_info "Fetching latest release tag from GitHub API for $CAPTAINCORE_REPO..."
LATEST_TAG_JSON=$(curl -s "https://api.github.com/repos/${CAPTAINCORE_REPO}/releases/latest")

if echo "$LATEST_TAG_JSON" | grep -q '"tag_name":'; then
    LATEST_TAG=$(echo "$LATEST_TAG_JSON" | grep '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*//')
    log_info "Latest release tag: $LATEST_TAG"
else
    log_error "Could not fetch latest release tag from GitHub API. Response was:"
    log_error "$LATEST_TAG_JSON"
    log_info "Proceeding with a generic 'latest' download URL, which might not always point to the newest binary or might fail."
    LATEST_TAG="latest" # Fallback, but direct download might be tricky without asset name.
fi


ARCH=$(uname -m)
OS_TYPE="linux" # Assuming Linux, as per earlier checks
BINARY_ARCH="amd64" # Default

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    BINARY_ARCH="arm64"
elif [ "$ARCH" = "x86_64" ]; then
    BINARY_ARCH="amd64"
else
    log_error "Unsupported architecture: $ARCH for CaptainCore binary download."
    log_info "You may need to compile from source or find a compatible binary manually."
    exit 1
fi

# Construct the binary name - this is an assumption based on common GoReleaser patterns.
# Example: captaincore_1.2.3_linux_amd64
# If LATEST_TAG is "latest", this might not be the actual filename.
# A more robust way is to parse the assets list from the GitHub API JSON.
# For now, we'll try a common pattern. If goreleaser uses a simpler name like 'captaincore-linux-amd64', adjust this.
# Let's assume the binary name does NOT include the version for 'latest' direct download, or that goreleaser names it consistently.
# A common pattern for direct download without version in name might be: captaincore_linux_amd64
# Or, if the version IS in the name, the LATEST_TAG must be a proper version like v1.2.3

# Attempting to find a direct asset download URL from the GitHub API JSON
DOWNLOAD_URL=""
ASSET_NAME_PATTERN="captaincore_${OS_TYPE}_${BINARY_ARCH}" # Basic pattern
VERSIONED_ASSET_NAME_PATTERN="captaincore_$(echo "$LATEST_TAG" | sed 's/^v//')_${OS_TYPE}_${BINARY_ARCH}" # Pattern with version

if [ "$LATEST_TAG" != "latest" ] && echo "$LATEST_TAG_JSON" | grep -q '"browser_download_url":'; then
    # Try to find asset URL that matches the pattern
    DOWNLOAD_URL=$(echo "$LATEST_TAG_JSON" | grep '"browser_download_url":' | grep -i "$VERSIONED_ASSET_NAME_PATTERN" | sed -E 's/.*"browser_download_url": *"([^"]+)".*//' | head -n 1)
    if [ -z "$DOWNLOAD_URL" ]; then
         # Fallback to a simpler name if the versioned one isn't found (older goreleaser configs?)
         DOWNLOAD_URL=$(echo "$LATEST_TAG_JSON" | grep '"browser_download_url":' | grep -i "$ASSET_NAME_PATTERN" | sed -E 's/.*"browser_download_url": *"([^"]+)".*//' | head -n 1)
    fi
fi

if [ -z "$DOWNLOAD_URL" ]; then
    log_info "Could not determine specific asset download URL from GitHub API. Falling back to generic URL structure."
    # This structure assumes the repo uses GitHub Releases and assets are named predictably.
    # This might need adjustment based on actual release asset naming.
    # If LATEST_TAG is 'latest', this URL might be:
    # https://github.com/CaptainCore/captaincore/releases/latest/download/captaincore_linux_amd64
    # If LATEST_TAG is 'vX.Y.Z', this URL might be:
    # https://github.com/CaptainCore/captaincore/releases/download/vX.Y.Z/captaincore_X.Y.Z_linux_amd64
    # The GoReleaser config (.goreleaser.yml) would define the actual asset names.
    # Let's assume a common GoReleaser pattern where the version is part of the archive but maybe not the binary inside,
    # or the binary itself is named like 'captaincore_linux_amd64'.
    # This part is highly dependent on the actual release asset naming.
    # A common pattern for a direct binary (not archive) might be:
    RELEASE_ASSET_NAME="captaincore-${OS_TYPE}-${BINARY_ARCH}" # Common for direct binary
    if [ "$LATEST_TAG" = "latest" ]; then
        DOWNLOAD_URL="https://github.com/${CAPTAINCORE_REPO}/releases/latest/download/${RELEASE_ASSET_NAME}"
    else
        DOWNLOAD_URL="https://github.com/${CAPTAINCORE_REPO}/releases/download/${LATEST_TAG}/${RELEASE_ASSET_NAME}"
    fi
    log_info "Using fallback download URL: $DOWNLOAD_URL (This is a guess based on common patterns)"
fi


log_info "Downloading CaptainCore binary for $OS_TYPE $BINARY_ARCH from $DOWNLOAD_URL..."
TMP_CAPTAINCORE_BINARY="/tmp/captaincore_download"
rm -f "$TMP_CAPTAINCORE_BINARY" # Clean up previous attempt

# Use curl with -L to follow redirects, which is common for 'latest' release links
if curl -L -o "$TMP_CAPTAINCORE_BINARY" "$DOWNLOAD_URL"; then
    log_info "CaptainCore binary downloaded successfully to $TMP_CAPTAINCORE_BINARY."
else
    log_error "Failed to download CaptainCore binary. Tried URL: $DOWNLOAD_URL"
    log_error "Please check the CaptainCore GitHub releases page (https://github.com/${CAPTAINCORE_REPO}/releases) for the correct binary name and URL."
    log_error "If the binary name pattern (e.g., ${RELEASE_ASSET_NAME} or ${VERSIONED_ASSET_NAME_PATTERN}) is incorrect, this script needs adjustment."
    exit 1
fi

log_info "Making CaptainCore binary executable..."
chmod +x "$TMP_CAPTAINCORE_BINARY"

log_info "Moving CaptainCore binary to $CAPTAINCORE_INSTALL_PATH..."
if [ -f "$CAPTAINCORE_INSTALL_PATH" ]; then
    log_info "Removing existing file at $CAPTAINCORE_INSTALL_PATH."
    rm -f "$CAPTAINCORE_INSTALL_PATH"
fi
if mv "$TMP_CAPTAINCORE_BINARY" "$CAPTAINCORE_INSTALL_PATH"; then
    log_info "CaptainCore binary installed successfully to $CAPTAINCORE_INSTALL_PATH."
    # Verify by running a command, e.g., captaincore version
    if "$CAPTAINCORE_INSTALL_PATH" version &> /dev/null; then # Assuming 'captaincore version' is a valid command
        log_info "CaptainCore version: $($CAPTAINCORE_INSTALL_PATH version)"
    else
        log_info "Could not execute '$CAPTAINCORE_INSTALL_PATH version'. The binary might be corrupted or not a CaptainCore binary."
        log_info "If it requires subcommands, try '$CAPTAINCORE_INSTALL_PATH help' or similar."
    fi
else
    log_error "Failed to move CaptainCore binary to $CAPTAINCORE_INSTALL_PATH."
    log_error "Please check permissions for $CAPTAINCORE_INSTALL_PATH."
    exit 1
fi

log_info "=== Phase 3 (Git and CaptainCore Binary Installation) Complete ==="
echo

# --- Phase 4: Finalization and PATH Verification ---
log_info "=== Starting Phase 4: Finalization and PATH Verification ==="

# 1. Verify /usr/local/bin is in PATH
#    This is typically standard on most Linux systems.
#    The Go PATH setup in Phase 1 already created /etc/profile.d/golang.sh.
#    We just need to ensure the user is aware that a new shell session or sourcing profile is needed.

log_info "Verifying command availability..."

if command -v go &> /dev/null; then
    log_info "Go installation seems successful. Current version: $(go version | awk '{print $3}')"
else
    log_warning "Go command (go) not immediately found in PATH. A new shell session or 'source ${GO_PROFILE_SCRIPT}' may be needed."
fi

if command -v wp &> /dev/null && wp --info &> /dev/null; then
    log_info "WP-CLI installation seems successful. Current version: $(wp cli version --quiet)"
else
    log_warning "WP-CLI command (wp) not immediately found or not functioning. A new shell session may be needed."
fi

if command -v captaincore &> /dev/null; then
    # Attempt to get version. This might fail if 'captaincore version' isn't the command.
    CAPTAINCORE_VERSION_OUTPUT=$($CAPTAINCORE_INSTALL_PATH version 2>/dev/null || echo "version command not found or failed")
    log_info "CaptainCore installation seems successful. Path: $(command -v captaincore)."
    log_info "CaptainCore version output: ${CAPTAINCORE_VERSION_OUTPUT}"
else
    log_warning "CaptainCore command (captaincore) not immediately found in PATH. A new shell session may be needed."
fi


# 2. Concluding Messages
echo
log_info "---------------------------------------------------------------------"
log_info "CaptainCore Dependency Installation Script Finished"
log_info "---------------------------------------------------------------------"
log_info "Summary of actions:"
log_info "- Checked/Installed Go (Golang)"
log_info "- Checked/Installed WP-CLI"
log_info "- Checked/Installed Git"
log_info "- Checked/Installed CaptainCore binary"
log_info "- PATH configuration for Go was set up in ${GO_PROFILE_SCRIPT}"
echo
log_info "IMPORTANT:"
log_info "To ensure all installed tools (Go, WP-CLI, CaptainCore) are available in your"
log_info "current terminal session, you may need to source your profile file or"
log_info "open a new terminal session."
log_info "Example for bash (if you updated .bashrc or for /etc/profile.d scripts):"
log_info "  source ~/.bashrc  OR for system-wide changes like /etc/profile.d:"
log_info "  Logout and log back in, or open a new terminal."
log_info "The script attempted to update PATH for the current execution where possible."
echo
log_info "If you encounter issues, please check the logs above and ensure that"
log_info "/usr/local/go/bin and /usr/local/bin are in your system's PATH."
log_info "=== Installation Script Complete ==="
echo
