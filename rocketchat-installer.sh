#!/bin/bash
set -e

# --- Visual Helpers ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() { echo -e "\n${CYAN}### $1 ###${NC}"; }
print_step() { echo -e "\n${YELLOW}==> $1${NC}"; }
print_info() { echo -e "${NC}    $1"; }
print_success() { echo -e "${GREEN}    OK: $1${NC}"; }
print_warning() { echo -e "${YELLOW}    WARNING: $1${NC}"; }
print_error() { echo -e "${RED}    ERROR: $1${NC}"; }

# --- 1. Root Check ---
if [ "$EUID" -ne 0 ]; then 
  print_error "Please run as root (use sudo)"
  exit 1
fi

# --- 2. Input Wizard (Runs First) ---
clear
echo -e "${GREEN}"
echo "=================================================="
echo "      Rocket.Chat One-Click Installer             "
echo "=================================================="
echo -e "${NC}"

print_info "We need to gather some information before we start."
print_info "Please answer the following questions."
echo ""

# > Input: Domain
while [[ -z "$INPUT_URL" ]]; do
  read -p "1. Enter your Domain or IP (e.g. chat.mydomain.com): " INPUT_URL < /dev/tty
  if [[ -z "$INPUT_URL" ]]; then echo -e "${RED}   Domain is required.${NC}"; fi
done

# Clean URL
if [[ ! $INPUT_URL =~ ^http ]]; then
    ROOT_URL="http://$INPUT_URL"
    DOMAIN_ONLY="$INPUT_URL"
else
    ROOT_URL="$INPUT_URL"
    # Extract domain from url for DNS check
    DOMAIN_ONLY=$(echo "$INPUT_URL" | awk -F/ '{print $3}')
fi

# > Input: Port
read -p "2. Server Port (default: 3000): " HOST_PORT < /dev/tty
HOST_PORT=${HOST_PORT:-3000}

# > Input: Version
read -p "3. Rocket.Chat Version (default: latest): " RC_VERSION < /dev/tty
RC_VERSION=${RC_VERSION:-latest}

# > Input: SSL Email (For future use or SSL setup)
read -p "4. Email for SSL/Alerts (optional, press Enter to skip): " SSL_EMAIL < /dev/tty
SSL_EMAIL=${SSL_EMAIL:-"admin@example.com"}

# > Input: Mirror
echo ""
print_info "If Docker Hub is blocked in your region, enter a mirror URL."
read -p "5. Docker Mirror URL (default: None, press Enter to skip): " DOCKER_MIRROR < /dev/tty


# --- 3. DNS Check with Retry ---
print_header "Checking DNS Resolution"

# Get Public IP
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s ifconfig.me)
print_info "Your Public IP seems to be: $PUBLIC_IP"

while true; do
    print_info "Checking if '$DOMAIN_ONLY' points to '$PUBLIC_IP'..."
    
    # Try to resolve domain
    if command -v dig &> /dev/null; then
        RESOLVED_IP=$(dig +short "$DOMAIN_ONLY" | head -n1)
    elif command -v nslookup &> /dev/null; then
        RESOLVED_IP=$(nslookup "$DOMAIN_ONLY" | grep 'Address' | tail -n1 | awk '{print $2}')
    else
        RESOLVED_IP="unknown" # skip check if tools missing
    fi

    if [[ "$RESOLVED_IP" == "$PUBLIC_IP" ]]; then
        print_success "DNS verified! ($DOMAIN_ONLY -> $PUBLIC_IP)"
        break
    elif [[ "$RESOLVED_IP" == "unknown" ]]; then
        print_warning "Could not verify DNS (dig/nslookup missing). Proceeding anyway."
        break
    else
        echo -e "${RED}    MISMATCH: '$DOMAIN_ONLY' resolves to '$RESOLVED_IP', but your IP is '$PUBLIC_IP'.${NC}"
        echo -e "${YELLOW}    Please update your DNS A record.${NC}"
        
        read -p "    [R]etry check or [I]gnore and proceed? (r/I): " DNS_CHOICE < /dev/tty
        case "${DNS_CHOICE,,}" in
            r|retry) continue ;;
            *) 
               print_warning "Ignoring DNS mismatch. Proceeding..."
               break 
               ;;
        esac
    fi
done


# --- 4. OS & Environment Prep ---
print_header "Preparing Environment"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION_CODENAME=$VERSION_CODENAME
    UBUNTU_CODENAME=$UBUNTU_CODENAME
fi

if command -v apt-get >/dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf >/dev/null; then
    PKG_MANAGER="dnf"
elif command -v yum >/dev/null; then
    PKG_MANAGER="yum"
else
    print_error "Unsupported package manager."
    exit 1
fi

# Function: Install Docker
install_docker() {
    print_step "Checking Docker Installation..."
    
    if ! command -v curl &> /dev/null; then
        $PKG_MANAGER install -y curl &> /dev/null
    fi

    if command -v docker &> /dev/null; then
        local current_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        print_success "Docker already installed ($current_version)"
    else
        print_info "Installing Docker..."
        
        # Simple Logic: Try Official -> Fail -> Try System
        if [ "$PKG_MANAGER" == "apt" ]; then
            apt update -qq
            if ! curl -fsSL https://get.docker.com | sh; then
                 print_warning "Standard installer failed. Trying system repos..."
                 apt install -y docker.io docker-compose
            fi
        else
             curl -fsSL https://get.docker.com | sh || $PKG_MANAGER install -y docker
        fi
        
        systemctl start docker
        systemctl enable docker &> /dev/null
        print_success "Docker Installed."
    fi

    # Configure Mirror if requested
    if [ -n "$DOCKER_MIRROR" ]; then
        print_step "Configuring Docker Mirror..."
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$DOCKER_MIRROR"]
}
EOF
        systemctl restart docker
        print_success "Mirror set to $DOCKER_MIRROR"
    fi
}

install_docker

# --- 5. Generate Config ---
print_header "Generating Configuration"

TEMPLATE_FILE="docker-compose.yml.template"

# Check if template exists (Handle curl | bash execution context)
if [ ! -f "$TEMPLATE_FILE" ]; then
    # If running from curl, we might not have the file. 
    # Attempt to download it if missing, OR fail if we assume the repo is cloned.
    # Assuming user cloned repo OR has file.
    if [ ! -f "docker-compose.yml.template" ]; then
         print_error "docker-compose.yml.template not found."
         print_info "Please ensure you have the template file in this directory."
         exit 1
    fi
fi

echo "Generating docker-compose.yml..."
sed -e "s|{{RC_VERSION}}|$RC_VERSION|g" \
    -e "s|{{HOST_PORT}}|$HOST_PORT|g" \
    -e "s|{{ROOT_URL}}|$ROOT_URL|g" \
    $TEMPLATE_FILE > docker-compose.yml

print_success "Configuration generated."


# --- 6. Deployment ---
print_header "Starting Rocket.Chat"

if docker compose version >/dev/null 2>&1; then
    CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    CMD="docker-compose"
else
    print_error "Docker Compose not found."
    exit 1
fi

$CMD up -d

print_header "Installation Complete!"

# --- 7. Final Output & Firewall ---
echo -e "${GREEN}Rocket.Chat is running!${NC}"
echo -e "URL:  ${CYAN}$ROOT_URL${NC}"
echo -e "Port: ${CYAN}$HOST_PORT${NC}"

print_step "Firewall Commands (Copy/Paste if needed):"
if [ "$PKG_MANAGER" == "apt" ]; then
    echo -e "${YELLOW}ufw allow $HOST_PORT/tcp${NC}"
    echo -e "${YELLOW}ufw allow 80/tcp${NC}"
    echo -e "${YELLOW}ufw allow 443/tcp${NC}"
    echo -e "${YELLOW}ufw reload${NC}"
elif [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
    echo -e "${YELLOW}firewall-cmd --permanent --add-port=$HOST_PORT/tcp${NC}"
    echo -e "${YELLOW}firewall-cmd --reload${NC}"
fi

echo ""
echo "----------------------------------------------------------------"
echo -e "${CYAN}   Created by Ramtin${NC}"
echo -e "   YouTube:   youtube.com/@ramtin"
echo -e "   Instagram: instagram.com/ramtin"
echo -e "   Web:       ramtin.net"
echo "----------------------------------------------------------------"
echo ""
