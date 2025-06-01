# CaptainCore Server Setup Guide

This guide outlines the steps required to set up CaptainCore on a server.

## Automated Setup Script

For a quicker, automated setup on a fresh Ubuntu server, you can use the `setup.sh` script available in the root of this repository. This script attempts to perform most of the steps detailed below.

To use it:
1. Download or clone the repository.
2. Navigate to the repository directory.
3. Run the script with sudo: `sudo ./setup.sh`

It is still recommended to read through this manual guide to understand the components and configuration involved.

## 1. Prerequisites

Before you begin, ensure you have the following:

*   **Ubuntu VPS:** A virtual private server running Ubuntu.
*   **WordPress Site with CaptainCore Manager:** A WordPress installation where you can install the [CaptainCore Manager plugin](https://github.com/CaptainCore/captaincore-manager). This site will serve as the user interface for your CaptainCore instance.

## 2. Installation

CaptainCore provides an automated installation script that simplifies the setup process. This script also handles the installation of required third-party dependencies.

To install CaptainCore on your Ubuntu VPS, run the following command:

```bash
curl -s https://captaincore.io/install.sh | sudo bash
```

This command will download and execute the installation script. Ensure you run this as a user with sudo privileges.

## 3. Web Server Configuration (Caddy)

The `captaincore server` command starts the CaptainCore application, which listens on port 8000 by default. To make it accessible publicly over HTTPS, it's recommended to use a reverse proxy. This guide uses Caddy.

### 3.1. Install Caddy

Refer to the official Caddy documentation for instructions on [installing Caddy](https://caddyserver.com/docs/install#static-binaries) and setting it up as a [Linux service](https://caddyserver.com/docs/install#linux-service).

### 3.2. Configure Caddy

Create a `Caddyfile` in your user's home directory (e.g., `/home/username/Caddyfile`) with the following configuration. Replace `captaincore.my-domain.tld` with your actual public domain name, and ensure your DNS records point this domain to your server's IP address.

```caddy
captaincore.my-domain.tld {
    reverse_proxy :8000
}
```

### 3.3. Update Caddy Service

Modify the default Caddy Linux service file. The `ExecStart` and `ExecReload` lines should be updated to use your `Caddyfile`. Replace `username` with your actual username.

Open the Caddy service file (usually located at `/etc/systemd/system/caddy.service` or a similar path) and update the following lines:

```ini
ExecStart=/usr/bin/caddy run --environ --config /home/username/Caddyfile
ExecReload=/usr/bin/caddy reload --config /home/username/Caddyfile
```

After editing the service file, reload the systemd daemon:

```bash
sudo systemctl daemon-reload
```

Then, enable and start the Caddy service if it's not already running:

```bash
sudo systemctl enable caddy
sudo systemctl start caddy
```

## 4. CaptainCore Service Setup

To ensure CaptainCore runs continuously in the background, you should set it up as a Linux service.

### 4.1. Create systemd Service File

Create a new service file at `/etc/systemd/system/captaincore.service`. Replace `username` with the actual username that will run the CaptainCore service (this should typically be the same user under which Caddy is configured if following the previous steps, or a dedicated user for CaptainCore). The `Group` can also be set to the same group as Caddy (e.g., `caddy`) or a relevant group for your setup.

```ini
[Unit]
Description=CaptainCore
Documentation=https://docs.captaincore.io
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=simple
User=username
Group=caddy
ExecStart=/usr/bin/captaincore server
Restart=always
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
```

**Note on `AmbientCapabilities=CAP_NET_BIND_SERVICE`:** This line allows CaptainCore to bind to privileged ports (like 80 or 443) if needed, though in our Caddy setup, it runs on port 8000. It's good practice if CaptainCore might directly handle web traffic in other configurations.

### 4.2. Enable and Start the Service

After creating the service file, reload the systemd daemon, then enable and start the CaptainCore service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable captaincore
sudo systemctl start captaincore
```

You can check the status of the service using:

```bash
sudo systemctl status captaincore
```

## 5. WordPress GUI Connection

CaptainCore can be managed through a graphical user interface (GUI) hosted on a WordPress site. This requires installing the CaptainCore Manager plugin on a WordPress site of your choice.

### 5.1. Install CaptainCore Manager Plugin

1.  Download the latest version of the [CaptainCore Manager plugin](https://github.com/CaptainCore/captaincore-manager/releases) (usually a `.zip` file).
2.  On your chosen WordPress site, navigate to "Plugins" > "Add New".
3.  Click "Upload Plugin" and select the downloaded `.zip` file.
4.  Install and activate the plugin.

### 5.2. Connect to CaptainCore Instance

Once activated, the CaptainCore Manager plugin will typically prompt you to connect to your CaptainCore instance. You will need to provide details about your self-hosted CaptainCore server, such as its URL (e.g., `https://captaincore.my-domain.tld` that you configured with Caddy).

Follow the on-screen instructions within the plugin to establish the connection. This will allow you to manage your CaptainCore-linked sites through the WordPress admin interface.

## 6. Cron Job Configuration

Many CaptainCore tasks, such as site monitoring, updates, and backups, are designed to run on a schedule. This is achieved using cron jobs.

### 6.1. Edit Crontab

Open your system's crontab for editing. It's usually best to edit the crontab for the user that CaptainCore runs as, or a user with appropriate permissions.

```bash
crontab -e
```

### 6.2. Add CaptainCore Commands

Add the following lines to your crontab. These are examples, and you may need to adjust the schedules and commands based on your specific requirements.

**Important:** Some CaptainCore bash scripts call other `captaincore` commands. For these to work correctly, ensure the `PATH` environment variable at the top of your crontab includes the directory where the `captaincore` binary is installed (typically `/usr/bin` or `/usr/local/bin` if installed via the script).

```cron
# m h  dom mon dow   command
PATH=/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin

# Monitor production sites every 10 minutes
*/10 * * * * captaincore monitor @production --fleet

# Scan for errors on production sites nightly
45 18 * * * captaincore scan-errors @production --fleet

# Run updates for production sites with 'updates-on' tag weekly (Wednesday at 09:15)
15 09 * * 3 captaincore update @production.updates-on --fleet

# Run updates for staging sites with 'updates-on' tag quarterly (1st of the month at 00:15)
15 00 1 */3 * captaincore update @staging.updates-on --fleet

# Generate backups for production sites nightly
03 00 * * * captaincore backup generate @production --fleet

# Generate quicksaves for all sites nightly
01 00 * * * captaincore quicksave generate @all --fleet
```

### 6.3. Save Crontab

Save the changes to your crontab. The cron daemon will automatically pick up the new schedule.

This completes the basic server setup for CaptainCore. Refer to the [official CaptainCore documentation](https://docs.captaincore.io) for more advanced configurations and command usage.
