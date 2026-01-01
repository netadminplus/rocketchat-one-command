#!/bin/bash

# ==============================================================================
#  Rocket.Chat Installer by NetAdminPlus (Ramtin)
#  Website: netadminplus.com | YouTube: netadminplus | Instagram: netadminplus
# ==============================================================================

# --- Visual Helpers ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_banner() {
    clear
    echo -e "${GREEN}==============================================================${NC}"
    echo -e "${GREEN}   Rocket.Chat One-Click Installer by NetAdminPlus (Ramtin)   ${NC}"
    echo -e "${GREEN}==============================================================${NC}"
    echo -e "   Website: netadminplus.com"
    echo -e "   YouTube: youtube.com/@netadminplus"
    echo -e ""
}

print_step() { echo -e "\n${YELLOW}==> $1${NC}"; }
print_success() { echo -e "${GREEN}    OK: $1${NC}"; }
print_error() { echo -e "${RED}    ERROR: $1${NC}"; }
print_info() { echo -e "    $1"; }

# --- 1. Root Check ---
if [ "$EUID" -ne 0 ]; then 
  print_error "Please run as root (use sudo)"
  exit 1
fi

print_banner
print_step "Initializing Installer..."

# --- 2. OS Detection ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    print_error "Unsupported OS. Could not detect distribution."
    exit 1
fi

if command -v apt-get >/dev/null; then PKG_MANAGER="apt"; 
elif command -v dnf >/dev/null; then PKG_MANAGER="dnf";
elif command -v yum >/dev/null; then PKG_MANAGER="yum";
else
    print_error "Unsupported package manager."
    exit 1
fi

# --- 3. Configuration Gathering ---
print_step "Configuration Setup"

# Domain
read -p "1. Enter your Domain (e.g., chat.mydomain.com): " DOMAIN < /dev/tty
if [ -z "$DOMAIN" ]; then print_error "Domain is required!"; exit 1; fi

# Email for SSL
read -p "2. Email for SSL Alerts (optional, enter to skip): " EMAIL < /dev/tty
if [ -z "$EMAIL" ]; then EMAIL="admin@$DOMAIN"; fi

# Version
read -p "3. Rocket.Chat Version (default: latest): " RC_VERSION < /dev/tty
RC_VERSION=${RC_VERSION:-latest}

# Mirror Check
print_info "Checking Docker Hub accessibility..."
if curl --connect-timeout 3 -s https://hub.docker.com >/dev/null; then
    print_success "Docker Hub is accessible."
else
    echo -e "${YELLOW}    Warning: Docker Hub seems blocked.${NC}"
    read -p "    Enter a Docker Mirror URL (e.g., https://docker.iranserver.com) or press Enter to skip: " DOCKER_MIRROR < /dev/tty
fi

# --- 4. DNS Verification ---
print_step "Verifying DNS"
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me/ip)
print_info "Server Public IP: $PUBLIC_IP"

if command -v host &> /dev/null; then
    DOMAIN_IP=$(host $DOMAIN | grep "has address" | head -n 1 | awk '{print $4}')
    if [ "$DOMAIN_IP" == "$PUBLIC_IP" ]; then
        print_success "DNS verified ($DOMAIN -> $PUBLIC_IP)"
    else
        echo -e "${YELLOW}    WARNING: DNS mismatch! SSL generation may fail.${NC}"
        echo "    Domain points to: $DOMAIN_IP"
        echo "    Server IP is:     $PUBLIC_IP"
        read -p "    Continue anyway? (y/n): " CONFIRM < /dev/tty
        if [[ "$CONFIRM" != "y" ]]; then exit 1; fi
    fi
fi

# --- 5. Install Docker ---
print_step "Installing/Updating Docker"

if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    if [ ! -z "$DOCKER_MIRROR" ]; then
        sh get-docker.sh --mirror "$DOCKER_MIRROR"
    else
        sh get-docker.sh
    fi
    rm get-docker.sh
    print_success "Docker installed."
else
    print_success "Docker already installed."
fi

# Configure Mirror in daemon.json if provided
if [ -n "$DOCKER_MIRROR" ]; then
    mkdir -p /etc/docker
    if [ ! -f /etc/docker/daemon.json ]; then
        echo "{ \"registry-mirrors\": [\"$DOCKER_MIRROR\"] }" > /etc/docker/daemon.json
        systemctl restart docker
        print_success "Docker Mirror configured."
    fi
fi

# --- 6. Download & Generate Config ---
print_step "Downloading Configuration Template"
TEMPLATE_FILE="docker-compose.yml.template"
rm -f "$TEMPLATE_FILE"
TEMPLATE_URL="https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/docker-compose.yml.template"

if curl -s -f -O "$TEMPLATE_URL"; then
    print_success "Template downloaded."
else
    print_error "Failed to download template. Check repository URL."
    exit 1
fi

print_step "Generating Environment"

# Generate Random Passwords
MONGO_PASS=$(openssl rand -hex 16)
MONGO_USER="root"

# Create .env file
echo "DOMAIN=$DOMAIN" > .env
echo "LETSENCRYPT_EMAIL=$EMAIL" >> .env
echo "RC_VERSION=$RC_VERSION" >> .env
echo "MONGO_USER=$MONGO_USER" >> .env
echo "MONGO_PASS=$MONGO_PASS" >> .env

# --- CRITICAL FIX: Generate MongoDB KeyFile ---
print_info "Generating MongoDB KeyFile..."
openssl rand -base64 756 > mongodb.key
chmod 400 mongodb.key
# Attempt to set ownership to default mongo user (999) if possible, otherwise rely on read permissions
chown 999:999 mongodb.key 2>/dev/null || true
print_success "KeyFile generated."

# Generate docker-compose.yml
cp docker-compose.yml.template docker-compose.yml

print_success "Configuration generated."

# --- 7. Start Services ---
print_step "Starting Services"

if ! docker compose version &> /dev/null; then
    $PKG_MANAGER install -y docker-compose-plugin &> /dev/null
fi

docker compose up -d

if [ $? -eq 0 ]; then
    print_banner
    echo -e "${GREEN}   INSTALLATION SUCCESSFUL!${NC}"
    echo -e "   --------------------------------------------------------------"
    echo -e "   Rocket.Chat URL:  https://$DOMAIN"
    echo -e "   SSL Status:       Auto-configured via Traefik (Let's Encrypt)"
    echo -e "   Data Directory:   $(pwd)"
    echo -e "   MongoDB User:     $MONGO_USER"
    echo -e "   MongoDB Pass:     (Check .env file)"
    echo -e "   --------------------------------------------------------------"
    echo -e "   Note: It may take 1-2 minutes for the server to start fully."
    echo -e "   To view logs: docker compose logs -f"
else
    print_error "Docker failed to start."
    exit 1
fi
