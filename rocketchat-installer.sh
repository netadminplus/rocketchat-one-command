#!/bin/bash
# Remove set -e because it kills the script if 'read' behaves oddly on some systems
# set -e 

# --- Visual Helpers ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

print_step "Initializing Rocket.Chat Auto-Installer..."

# --- 2. OS Detection ---
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
    print_error "Unsupported package manager. Only apt, dnf, and yum are supported."
    exit 1
fi

# --- 3. Gather Configuration ---
print_step "Configuration Setup"

# Get Domain/URL
# ADDED < /dev/tty to fix the pipe crash
read -p "Enter the Full Domain/URL (e.g., https://chat.mydomain.com): " INPUT_URL < /dev/tty
if [ -z "$INPUT_URL" ]; then
    print_error "Domain/URL is required!"
    exit 1
fi
# Ensure protocol exists
if [[ ! $INPUT_URL =~ ^http ]]; then
    ROOT_URL="http://$INPUT_URL"
else
    ROOT_URL="$INPUT_URL"
fi

# Get Port
read -p "Enter the Host Port to listen on (default: 3000): " HOST_PORT < /dev/tty
HOST_PORT=${HOST_PORT:-3000}

# Get Version
read -p "Enter Rocket.Chat Version (default: latest): " RC_VERSION < /dev/tty
RC_VERSION=${RC_VERSION:-latest}

# Get Mirror (Useful for restricted regions)
echo ""
print_info "If you are in a region where Docker Hub is blocked, enter a mirror URL."
read -p "Docker Registry Mirror (leave empty if not needed): " DOCKER_REGISTRY_MIRROR < /dev/tty

# --- 4. Install Docker Function ---
install_docker() {
    print_step "Installing/Updating Docker..."
    
    # Pre-req: Ensure curl is installed
    if ! command -v curl &> /dev/null; then
        print_info "Installing curl..."
        $PKG_MANAGER install -y curl &> /dev/null
    fi

    if command -v docker &> /dev/null; then
        local current_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        print_info "Docker is already installed (version: $current_version)"
    else
        print_info "Docker not found. Starting installation..."
        
        case $PKG_MANAGER in
            apt)
                # Clean up old versions
                apt remove -y docker docker-engine docker.io containerd runc &> /dev/null || true
                
                # Method 1: Try official repository
                print_info "Attempting Docker installation from official repository..."
                install -m 0755 -d /etc/apt/keyrings
                
                if curl -fsSL https://download.docker.com/linux/$DISTRO/gpg -o /etc/apt/keyrings/docker.asc 2>/dev/null; then
                    chmod a+r /etc/apt/keyrings/docker.asc
                    cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$DISTRO
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
                    apt update -qq 2>&1 | grep -v "Failed to fetch" || true
                    
                    if apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | grep -q "Unable to locate"; then
                        print_warning "Official repository unavailable. Switching to System Repository..."
                        rm -f /etc/apt/sources.list.d/docker.sources
                        apt update -qq
                        apt install -y docker.io docker-compose -qq
                    else
                        print_success "Docker installed from official repository"
                    fi
                else
                    print_warning "Official GPG key download failed. Switching to System Repository..."
                    apt update -qq
                    apt install -y docker.io docker-compose -qq
                fi
                ;;
            dnf|yum)
                $PKG_MANAGER install -y yum-utils &> /dev/null
                if yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &> /dev/null; then
                     if ! $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &> /dev/null; then
                        print_warning "Official repo failed. Trying system repo..."
                        $PKG_MANAGER install -y docker &> /dev/null
                     fi
                else
                    $PKG_MANAGER install -y docker &> /dev/null
                fi
                ;;
        esac
    fi
    
    # Start Docker
    systemctl start docker
    systemctl enable docker &> /dev/null
    
    # Configure Mirror if user provided one
    if [ -n "$DOCKER_REGISTRY_MIRROR" ]; then
        print_info "Configuring Docker registry mirror: $DOCKER_REGISTRY_MIRROR"
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$DOCKER_REGISTRY_MIRROR"]
}
EOF
        systemctl restart docker
        print_success "Mirror configured."
    fi

    # Final Check
    if ! command -v docker &> /dev/null; then
        print_error "Docker installation failed."
        exit 1
    fi
    print_success "Docker is ready."
}

# --- 5. Execution ---

# Run Docker Installer
install_docker

# --- CRITICAL: Download Template ---
print_step "Downloading Configuration Template"
TEMPLATE_FILE="docker-compose.yml.template"
# Clean up old file to ensure fresh download
rm -f "$TEMPLATE_FILE"

# CHANGE THIS URL TO YOUR EXACT REPO URL
TEMPLATE_URL="https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/docker-compose.yml.template"

if curl -s -f -O "$TEMPLATE_URL"; then
    print_success "Template downloaded."
else
    print_error "Failed to download $TEMPLATE_FILE from GitHub."
    exit 1
fi

# Check for Template
print_step "Generating Configuration"
if [ ! -f "$TEMPLATE_FILE" ]; then
    print_error "$TEMPLATE_FILE not found in current directory!"
    exit 1
fi

# Generate docker-compose.yml
# Using | delimiter to avoid issues with URLs containing /
sed -e "s|{{RC_VERSION}}|$RC_VERSION|g" \
    -e "s|{{HOST_PORT}}|$HOST_PORT|g" \
    -e "s|{{ROOT_URL}}|$ROOT_URL|g" \
    $TEMPLATE_FILE > docker-compose.yml

print_success "docker-compose.yml generated for $ROOT_URL on port $HOST_PORT"

# Run Containers
print_step "Starting Rocket.Chat..."

if docker compose version >/dev/null 2>&1; then
    docker compose up -d
elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
else
    print_error "Could not find 'docker compose' or 'docker-compose' executable."
    exit 1
fi

print_step "Deployment Complete!"
echo -e "${GREEN}Rocket.Chat should be reachable at: $ROOT_URL${NC}"
echo -e "Note: First launch takes about 30-60 seconds to initialize the database."
