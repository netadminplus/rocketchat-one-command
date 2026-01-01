**English** | [فارسی](README.md)

---

# 🚀 RocketChat One-Command Installer

<div align="center">

![RocketChat](https://img.shields.io/badge/RocketChat-Latest-red)
![Docker](https://img.shields.io/badge/Docker-Required-blue)
![License](https://img.shields.io/badge/License-MIT-green)

**Easy RocketChat deployment with Docker, SSL, and automatic configuration**

Created by [Ramtin - NetAdminPlus](https://netadminplus.com)

[YouTube](https://youtube.com/@netadminplus) • [Website](https://netadminplus.com) • [Instagram](https://instagram.com/netadminplus)

</div>

---

## ✨ Features

- 🎯 **One-command installation** - Get RocketChat running in minutes
- 🔒 **Automatic SSL** - Let's Encrypt certificates with auto-renewal
- 📂 **Custom Installation Path** - Choose where to install (Default: `~/netadminplus-rocketchat`)
- 🤖 **Auto-Maintenance** - Optional Cronjob for weekly certificate checks/restarts
- ⏳ **Smart Wait System** - Checks logs and waits until Rocket.Chat is actually ready (No "Bad Gateway" errors)
- 🐳 **Docker-based** - Clean, isolated, and easy to manage
- 🌍 **Region Support** - Docker registry mirror support
- 🔐 **Auto-generated credentials** - Secure MongoDB passwords
- 📊 **System checks** - Validates requirements before installation
- 🔄 **DNS verification** - Checks domain configuration
- 🛡️ **Firewall Detection** - Suggests commands for UFW or Firewalld

---

## 📋 Requirements

### System Requirements
- **RAM**: Minimum 2GB (4GB recommended)
- **CPU**: 2+ cores recommended
- **Disk**: 20GB+ free space
- **OS**: Ubuntu 20.04+, Debian 10+, Rocky Linux 8+, CentOS 7+, AlmaLinux 8+

### Prerequisites
- Root or sudo access
- Domain/subdomain pointing to your server IP
- Ports 80 and 443 open (firewall)

---

## 🚀 Quick Start

### Recommended: Download and Run
```bash
curl -fsSL [https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/rocketchat-installer.sh](https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/rocketchat-installer.sh) -o rocketchat-installer.sh
chmod +x rocketchat-installer.sh
sudo ./rocketchat-installer.sh
```

### Alternative: One-Line Installation

⚠️ **Note**: The one-line method may have issues with interactive prompts. Use the download method above if you encounter problems.
```bash
curl -fsSL [https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/rocketchat-installer.sh](https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/rocketchat-installer.sh) | sudo bash
```

### Or Manual Installation
```bash
# Clone the repository
git clone [https://github.com/netadminplus/rocketchat-one-command.git](https://github.com/netadminplus/rocketchat-one-command.git)
cd rocketchat-one-command

# Make installer executable
chmod +x rocketchat-installer.sh

# Run installer
sudo ./rocketchat-installer.sh
```

---

## 📖 Installation Process

The installer will:

1. ✅ Check system requirements
2. ✅ Ask for **Installation Directory** (Default: `~/netadminplus-rocketchat`)
3. ✅ Create necessary data folders
4. ✅ Install/update Docker
5. ✅ Verify DNS configuration for your domain
6. ✅ Generate secure credentials
7. ✅ **Optionally setup a Cronjob** for weekly maintenance
8. ✅ Start Containers
9. ✅ **Wait for Server:** Monitors logs until "SERVER RUNNING" appears
10. ✅ Display specific Firewall instructions

---

## 📂 Project Structure

Default installation location is `~/netadminplus-rocketchat`:
```
netadminplus-rocketchat/
├── docker-compose.yml       # Docker Compose configuration
├── .env                     # Environment variables & credentials
├── renew-cert.sh            # Maintenance script (run by Cron)
├── cron.log                 # Cronjob logs
├── data/
│   ├── mongodb/             # MongoDB database files
│   ├── uploads/             # RocketChat file uploads
│   └── certs/               # SSL certificates
└── rocketchat-installer.sh  # Installer script
```

---

## 🔧 Configuration

### Environment Variables

All credentials and configuration are stored in `.env` file:
```bash
cat .env
```

### Accessing RocketChat

After installation completes:
```
URL: [https://your-domain.com](https://your-domain.com)
Admin Setup: First user to register becomes admin
```

---

## 🔒 Firewall Configuration

The installer attempts to detect your firewall manager (UFW or Firewalld) and provides the exact commands.

**Example (UFW):**
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

---

## 🤖 Automatic Maintenance

During installation, you can enable a Cronjob that:
- Runs weekly (Sunday at 3:00 AM).
- Executes `renew-cert.sh`.
- Restarts Traefik to ensure fresh SSL certificates are loaded.

---

## 🔄 Updates

See [UPDATE.md](docs/UPDATE.md) for instructions on updating RocketChat.

---

## 🐛 Troubleshooting

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and solutions.

---

## 📁 Important Files

- **`.env`** - Contains all credentials (MongoDB password, etc.)
- **`docker-compose.yml`** - Service configuration
- **`data/`** - All persistent data (database, uploads, certificates)

### Backup Recommendations
```bash
# Backup data directory
tar -czf rocketchat-backup-$(date +%Y%m%d).tar.gz data/

# Backup environment file
cp .env .env.backup
```

---

## 🛑 Stopping/Starting RocketChat
```bash
# Navigate to install dir
cd ~/netadminplus-rocketchat

# Stop services
docker compose down

# Start services
docker compose up -d

# View logs
docker compose logs -f

# Restart services
docker compose restart
```

---

## 🗑️ Uninstallation
```bash
cd ~/netadminplus-rocketchat

# Stop and remove containers
docker compose down -v

# Go back one level
cd ..

# Remove data (⚠️ This deletes everything!)
rm -rf netadminplus-rocketchat/

# Optionally remove Docker
# Ubuntu/Debian: sudo apt remove docker-ce docker-ce-cli containerd.io
# Rocky/CentOS: sudo dnf remove docker-ce docker-ce-cli containerd.io
```

---

## 🤝 Support

- 📺 **YouTube**: [@netadminplus](https://youtube.com/@netadminplus)
- 🌐 **Website**: [netadminplus.com](https://netadminplus.com)
- 📸 **Instagram**: [@netadminplus](https://instagram.com/netadminplus)
- 🐛 **Issues**: [GitHub Issues](https://github.com/netadminplus/rocketchat-one-command/issues)

---

## 📝 License

MIT License - Feel free to use and modify

---

## 👨‍💻 Author

**Ramtin - NetAdminPlus**

Helping Iranian community deploy open-source communication tools

[YouTube](https://youtube.com/@netadminplus) • [Website](https://netadminplus.com) • [Instagram](https://instagram.com/netadminplus)

---

## ⭐ Show Your Support

If this project helped you, please:
- ⭐ Star this repository
- 📺 Subscribe to [NetAdminPlus YouTube](https://youtube.com/@netadminplus)
- 📢 Share with your friends and colleagues

---

<div align="center">

**Made with ❤️ for the Iranian Tech Community**

</div>
