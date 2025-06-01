# CaptainCore Self-Hosted Setup Guide

This guide will walk you through the steps to set up your own instance of CaptainCore.

---
# Prerequisites

To self-host CaptainCore, you will need:

*   A WordPress site with the [CaptainCore Manager plugin](https://github.com/CaptainCore/captaincore-manager) installed and activated.
*   An Ubuntu VPS (Virtual Private Server).

# Installing CaptainCore

On Linux, you can use the automated installer script. This script will check the current version of CaptainCore and install it if an update is available. It also handles the installation of several required third-party applications.

To run the installer, execute the following command in your terminal:

```bash
curl -s https://captaincore.io/install.sh | sudo bash
```

# Configure Caddy as a Reverse Proxy

Running `captaincore server` will start the server locally on port 8000. To make it publicly accessible over HTTPS, it's recommended to use a reverse proxy like Caddy.

1.  **Install Caddy:**
    Refer to the official Caddy documentation for instructions on [installing Caddy](https://caddyserver.com/docs/install#static-binaries) and running it as a [Linux service](https://caddyserver.com/docs/install#linux-service).

2.  **Create a Caddyfile:**
    Create a file named `Caddyfile` in your user's home directory (`~/Caddyfile`). Add the following configuration, replacing `captaincore.my-domain.tld` with your actual public domain name. Make sure your domain's DNS records point to your server's public IP address.

    ```json
    captaincore.my-domain.tld {
        reverse_proxy :8000
    }
    ```

3.  **Update Caddy Service:**
    Modify the default Caddy Linux service configuration. Update the `ExecStart` and `ExecReload` lines as follows, replacing `username` with your actual username:

    ```bash
    ExecStart=/usr/bin/caddy run --environ --config /home/username/Caddyfile
    ExecReload=/usr/bin/caddy reload --config /home/username/Caddyfile
    ```
    After saving the changes, reload the systemd daemon:
    ```bash
    sudo systemctl daemon-reload
    ```
    Then, enable and start the Caddy service:
    ```bash
    sudo systemctl enable caddy
    sudo systemctl start caddy
    ```

# Setup CaptainCore as a Linux Service

To ensure CaptainCore runs continuously in the background, you can set it up as a systemd service.

1.  **Create a service file:**
    Create a file named `captaincore.service` in the `/etc/systemd/system/` directory:

    ```bash
    sudo nano /etc/systemd/system/captaincore.service
    ```
    Add the following content to the file. Remember to replace `username` with your actual username and `caddy` with the appropriate group (if different, though `caddy` is common if you're using Caddy as a reverse proxy).

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

2.  **Enable and start the service:**
    After creating and saving the service file, run the following commands to reload the systemd daemon, enable the CaptainCore service to start on boot, and start it immediately:

    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable captaincore
    sudo systemctl start captaincore
    ```

    You can check the status of the service using:
    ```bash
    sudo systemctl status captaincore
    ```

# Connecting WordPress GUI to CaptainCore Instance

Any WordPress site can provide a Graphical User Interface (GUI) for your CaptainCore instance by using the CaptainCore Manager plugin.

1.  **Install the CaptainCore Manager Plugin:**
    Download the latest version of the [CaptainCore Manager plugin](https://github.com/CaptainCore/captaincore-manager) and install it on the WordPress site you want to use for the GUI.

2.  **Activate the Plugin:**
    Activate the CaptainCore WordPress plugin from your WordPress admin area.

3.  **Connect to Instance:**
    Once activated, the plugin will prompt you to connect to a CaptainCore instance. You will need to provide the necessary information from your CaptainCore server setup (e.g., the public URL you configured with Caddy and any API keys or connection details provided by your CaptainCore server). Follow the on-screen instructions to complete the connection.

# Crontab Configuration for Scheduled Tasks

The system crontab can be used to schedule recurring `captaincore` commands for various automated tasks.

1.  **Edit Crontab:**
    Open your system's crontab file for editing by running:
    ```bash
    crontab -e
    ```

2.  **Set PATH Variable:**
    Some CaptainCore bash scripts may call other `captaincore` commands. To ensure these work correctly when run via cron, you must define the `PATH` environment variable at the top of your crontab file. At a minimum, include `/usr/bin` and the path to your Go binaries (e.g., `/usr/local/go/bin` if Go is installed there).

3.  **Add Cron Jobs:**
    Below is an example crontab configuration. This example schedules `captaincore monitor` to run every 10 minutes, `captaincore scan-errors` nightly, `captaincore update` weekly for production sites and quarterly for staging sites, and `captaincore backup generate` and `captaincore quicksave generate` nightly. Adjust these examples to fit your needs.

    ```cron
    # m h  dom mon dow   command
    PATH=/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin

    */10 * * * * captaincore monitor @production --fleet
    45 18 * * * captaincore scan-errors @production --fleet
    15 09 * * 3 captaincore update @production.updates-on --fleet
    15 0 1 */3 * captaincore update @staging.updates-on --fleet
    03 00 * * * captaincore backup generate @production --fleet
    01 00 * * * captaincore quicksave generate @all --fleet
    ```
    Save and close the crontab file. The cron daemon will automatically pick up the changes.
