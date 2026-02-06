# Paqet Deploy

**Paqet Deploy** is an intelligent, automated installation and management suite for [Paqet](https://github.com/hanselime/paqet) Server. It handles system configuration, firewalls, and service management while providing auto-generated client connection scripts for seamless setup.

## Features

- **🚀 One-Click Installation**: Automated setup of dependencies, binary installation, and systemd service creation.
- **🤖 AI-Powered Operations**: Integrated AI analysis for intelligent error handling during installation and startup verification.
- **🔒 Secure Configuration**: Automatically generates strong secret keys and configures the KCP transport protocol.
- **🛡️ Firewall Optimization**: Configures `iptables` and `ufw` with performance-tuned rules (e.g., `NOTRACK` for high throughput).
- **📦 Client Distribution System**: Built-in HTTP server to distribute pre-configured `connect.sh` and `connect.bat` scripts to your clients.
- **🛠️ Management Tool**: Includes `paqet-deploy` CLI for easy log viewing, port changing, and uninstallation.

## Quick Install (Linux)

Run the following command on your server (requires `root`):

```bash
bash <(curl -sL https://raw.githubusercontent.com/MortezaVaezi2005/paqet-deploy/main/install.sh)
```

## How It Works

1.  **Server Setup**: The script installs Paqet, configures it to listen on your specified port (default `443`), and secures it with a random key.
2.  **Client Portal**: It spins up a lightweight distribution server on port `2026`.
3.  **Client Connection**: You simply run the provided curl command on your client device (PC, Mac, etc.) to automatically download and configure the client.

## Management

After installation, you can manage the service using the `paqet-deploy` command:

```bash
paqet-deploy
```

This opens a menu to:
- 📜 **View Logs**: Check real-time service logs.
- ⚙️ **Change Port**: Update the listening port and firewall rules automatically.
- 🗑️ **Uninstall**: Cleanly remove Paqet and all configurations.

## Client Setup

Once the server is installed, it will print instructions for connecting clients.

**Linux / macOS:**
```bash
curl http://<YOUR_SERVER_IP>:2026/connect.sh | bash
```

**Windows:**
Download and run the batch file:
`http://<YOUR_SERVER_IP>:2026/connect.bat`

## Requirements

- **OS**: Standard Linux distributions (Ubuntu 20.04+, Debian 10+ recommended).
- **Root Privileges**: The script creates services and modifies network settings.
- **Connectivity**: Public IP address.

## License

This project is licensed under the MIT License.
