#!/bin/bash

# ==============================================================================
#  Rocket.Chat Installer by NetAdminPlus (Ramtin)
#  Website: netadminplus.com | YouTube: netadminplus | Instagram: netadminplus
# ==============================================================================

# --- Visual Helpers ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
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

# --- 3. Directory Setup ---
print_step "Installation Directory"

# Default to a clean directory in the user's home
DEFAULT_DIR="$HOME/netadminplus-rocketchat"

echo -e "    Default installation path: ${CYAN}$DEFAULT_DIR${NC}"
read -p "    Do you want to install here? (y/n): " DIR_CONFIRM < /dev/tty
DIR_CONFIRM=${DIR_CONFIRM:-y} 

if [[ "$DIR_CONFIRM" =~ ^[Nn]$ ]]; then
    read -p "    Enter custom directory path: " INSTALL_DIR < /dev/tty
else
    INSTALL_DIR="$DEFAULT_DIR"
fi

# Create and enter directory
if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
    print_success "Created directory: $INSTALL_DIR"
fi

cd "$INSTALL_DIR" || { print_error "Could not access directory $INSTALL_DIR"; exit 1; }
print_success "Working directory set to: $(pwd)"

# --- 3.1 Create Data Structure (Fixing Missing Folders) ---
# We explicitly create these so 'ls' shows them and they map correctly
mkdir -p data/mongodb
mkdir -p data/uploads
mkdir -p data/certs
# Set generic permissions to avoid permission denied errors
chmod -R 755 data/
print_success "Data directories created (mongodb, uploads, certs)."


# --- 4. Configuration Gathering ---
print_step "Configuration Setup"

# Check if .env already exists
if [ -f .env ]; then
    echo -e "${YELLOW}    Existing configuration (.env) found in $(pwd)!${NC}"
    read -p "    Do you want to use the existing configuration? (y/n): " USE_EXISTING < /dev/tty
    if [[ "$USE_EXISTING" == "y" || "$USE_EXISTING" == "Y" ]]; then
        export $(grep -v '^#' .env | xargs)
        print_success "Loaded existing configuration."
        SKIP_GENERATION=true
    else
        print_info "Starting fresh configuration..."
    fi
fi

if [ "$SKIP_GENERATION" != "true" ]; then
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
fi

# --- 5. DNS Verification ---
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

# --- 6. Install Docker ---
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

# Configure Mirror in daemon.json
if [ -n "$DOCKER_MIRROR" ]; then
    mkdir -p /etc/docker
    if [ ! -f /etc/docker/daemon.json ]; then
        echo "{ \"registry-mirrors\": [\"$DOCKER_MIRROR\"] }" > /etc/docker/daemon.json
        systemctl restart docker
        print_success "Docker Mirror configured."
    fi
fi

# --- 7. Download & Generate Config ---
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

if [ "$SKIP_GENERATION" != "true" ]; then
    # Generate Random Passwords
    MONGO_PASS=$(openssl rand -hex 16)
    MONGO_USER="root"

    # Create .env file
    echo "DOMAIN=$DOMAIN" > .env
    echo "LETSENCRYPT_EMAIL=$EMAIL" >> .env
    echo "RC_VERSION=$RC_VERSION" >> .env
    echo "MONGO_USER=$MONGO_USER" >> .env
    echo "MONGO_PASS=$MONGO_PASS" >> .env
    
    print_info "New passwords generated."
else
    print_info "Using existing passwords from .env"
fi

# --- KeyFile Check ---
if [ ! -f mongodb.key ]; then
    print_info "Generating MongoDB KeyFile..."
    openssl rand -base64 756 > mongodb.key
    chmod 400 mongodb.key
    chown 999:999 mongodb.key 2>/dev/null || true
    print_success "KeyFile generated."
fi

cp docker-compose.yml.template docker-compose.yml
print_success "Configuration generated."

# --- 8. Cronjob Setup (NEW FEATURE) ---
print_step "Setting up Auto-Renew Cronjob"
read -p "    Enable automatic certificate renewal/maintenance cronjob? (y/n): " CRON_CONFIRM < /dev/tty
CRON_CONFIRM=${CRON_CONFIRM:-y}

if [[ "$CRON_CONFIRM" =~ ^[Yy]$ ]]; then
    # Create the renewal script
    cat <<EOF > renew-cert.sh
#!/bin/bash
# Auto-generated by NetAdminPlus Installer
cd $INSTALL_DIR
# Restarts traefik to ensure latest certs are applied and connection is fresh
docker compose restart traefik
EOF
    chmod +x renew-cert.sh
    
    # Add to crontab (Weekly execution on Sunday at 3am)
    CRON_CMD="$INSTALL_DIR/renew-cert.sh >> $INSTALL_DIR/cron.log 2>&1"
    (crontab -l 2>/dev/null | grep -v "renew-cert.sh"; echo "0 3 * * 0 $CRON_CMD") | crontab -
    
    print_success "Cronjob added! (Runs weekly at 3:00 AM)"
    print_info "Script location: $INSTALL_DIR/renew-cert.sh"
else
    print_info "Cronjob skipped."
fi

# --- 9. Start Services ---
print_step "Starting Services"

if ! docker compose version &> /dev/null; then
    $PKG_MANAGER install -y docker-compose-plugin &> /dev/null
fi

docker compose up -d

if [ $? -ne 0 ]; then
    print_error "Docker failed to start."
    exit 1
fi

# --- 10. Wait for Rocket.Chat ---
echo ""
print_info "Containers started. Waiting for Rocket.Chat to initialize..."
print_info "This usually takes 60-90 seconds (DB migration & startup)."

TIMEOUT_SEC=120
START_TIME=$(date +%s)
END_TIME=$((START_TIME + TIMEOUT_SEC))

while [ $(date +%s) -lt $END_TIME ]; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if docker compose logs --tail=20 2>/dev/null | grep -q "SERVER RUNNING"; then
        printf "\r\033[K"
        print_success "Rocket.Chat is UP and RUNNING!"
        break
    fi
    
    SPINNER="-\|/"
    SPIN_IDX=$((ELAPSED % 4))
    printf "\r[${SPINNER:$SPIN_IDX:1}] Finalizing setup... (${ELAPSED}s)"
    sleep 2
done
printf "\r\033[K"

# --- 11. Final Output ---
print_banner
echo -e "${GREEN}   INSTALLATION SUCCESSFUL!${NC}"
echo -e "   --------------------------------------------------------------"
echo -e "   Rocket.Chat URL:  https://$DOMAIN"
echo -e "   SSL Status:       Auto-configured via Traefik (Let's Encrypt)"
echo -e "   Data Directory:   $(pwd)/data"
echo -e "   MongoDB User:     $MONGO_USER"
echo -e "   MongoDB Pass:     (Check .env file)"
echo -e "   --------------------------------------------------------------"
echo -e "   ${CYAN}Note: If the site shows 'Bad Gateway' initially, please wait${NC}"
echo -e "   ${CYAN}another 30 seconds for the database to finish syncing.${NC}"
echo -e "   To view logs: docker compose logs -f"

# --- 12. Firewall Instructions ---
print_step "Firewall Configuration (Manual Action Required)"
print_info "For your site to be accessible, you MUST open ports 80 and 443."
echo ""

if command -v ufw >/dev/null; then
    echo -e "${YELLOW}   Detected UFW (Ubuntu/Debian). Run these commands:${NC}"
    echo -e "   sudo ufw allow 80/tcp"
    echo -e "   sudo ufw allow 443/tcp"
    echo -e "   sudo ufw reload"
elif command -v firewall-cmd >/dev/null; then
    echo -e "${YELLOW}   Detected Firewalld (CentOS/Rocky/Alma). Run these commands:${NC}"
    echo -e "   sudo firewall-cmd --permanent --add-service=http"
    echo -e "   sudo firewall-cmd --permanent --add-service=https"
    echo -e "   sudo firewall-cmd --reload"
else
    echo -e "${YELLOW}   Unknown Firewall. Please manually open TCP ports 80 and 443.${NC}"
    echo -e "   Example (iptables):"
    echo -e "   iptables -A INPUT -p tcp --dport 80 -j ACCEPT"
    echo -e "   iptables -A INPUT -p tcp --dport 443 -j ACCEPT"
fi
echo ""
