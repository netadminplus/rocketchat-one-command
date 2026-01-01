# 🚀 RocketChat Deploy - One-Click Installer

<div align="center">

![RocketChat](https://img.shields.io/badge/RocketChat-Latest-red)
![Docker](https://img.shields.io/badge/Docker-Required-blue)
![License](https://img.shields.io/badge/License-MIT-green)

**Easy RocketChat deployment for Iranian users with Docker, SSL, and automatic configuration**

Created by [Ramtin - NetAdminPlus](https://netadminplus.com)

[YouTube](https://youtube.com/@netadminplus) • [Website](https://netadminplus.com) • [Instagram](https://instagram.com/netadminplus)

</div>

---

## ✨ Features

- 🎯 **One-command installation** - Get RocketChat running in minutes
- 🔒 **Automatic SSL** - Let's Encrypt certificates with auto-renewal
- 🐳 **Docker-based** - Clean, isolated, and easy to manage
- 🌍 **Iranian-friendly** - Docker registry mirror support
- 🔐 **Auto-generated credentials** - Secure MongoDB passwords
- 📊 **System checks** - Validates requirements before installation
- 🔄 **DNS verification** - Checks domain configuration
- 🛡️ **Multi-distro support** - Ubuntu, Debian, Rocky Linux, CentOS, AlmaLinux
- 📁 **Organized structure** - All assets in one directory

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

### One-Line Installation
```bash
curl -fsSL https://raw.githubusercontent.com/netadminplus/rocketchat-deploy/main/rocketchat-installer.sh | sudo bash
```

### Or Manual Installation
```bash
# Clone the repository
git clone https://github.com/netadminplus/rocketchat-deploy.git
cd rocketchat-deploy

# Make installer executable
chmod +x rocketchat-installer.sh

# Run installer
sudo ./rocketchat-installer.sh
```

---

## 📖 Installation Process

The installer will:

1. ✅ Check system requirements (RAM, CPU, disk)
2. ✅ Detect your Linux distribution
3. ✅ Check Docker Hub accessibility
4. ✅ Install/update Docker and Docker Compose
5. ✅ Ask for your domain name
6. ✅ Verify DNS configuration
7. ✅ Ask for email (optional, for SSL notifications)
8. ✅ Ask for Docker registry mirror (if needed)
9. ✅ Generate secure MongoDB credentials
10. ✅ Setup Docker Compose configuration
11. ✅ Obtain SSL certificate from Let's Encrypt
12. ✅ Configure automatic certificate renewal
13. ✅ Display firewall configuration commands
14. ✅ Start RocketChat containers
15. ✅ Show access information and credentials

---

## 📂 Project Structure

After installation, your directory will contain:
```
rocketchat-deploy/
├── docker-compose.yml       # Docker Compose configuration
├── .env                      # Environment variables & credentials
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
URL: https://your-domain.com
Admin Setup: First user to register becomes admin
```

---

## 🔒 Firewall Configuration

The installer will display commands to configure your firewall. Example for UFW:
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

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
# Stop and remove containers
docker compose down -v

# Remove data (⚠️ This deletes everything!)
rm -rf data/

# Optionally remove Docker
# Ubuntu/Debian: sudo apt remove docker-ce docker-ce-cli containerd.io
# Rocky/CentOS: sudo dnf remove docker-ce docker-ce-cli containerd.io
```

---

## 🤝 Support

- 📺 **YouTube**: [@netadminplus](https://youtube.com/@netadminplus)
- 🌐 **Website**: [netadminplus.com](https://netadminplus.com)
- 📸 **Instagram**: [@netadminplus](https://instagram.com/netadminplus)
- 🐛 **Issues**: [GitHub Issues](https://github.com/netadminplus/rocketchat-deploy/issues)

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