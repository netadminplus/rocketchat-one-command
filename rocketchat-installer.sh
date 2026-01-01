#!/bin/bash

#############################################################################
# RocketChat One-Click Installer (Final Robust Version)
# 
# Created by: Ramtin - NetAdminPlus
# Website: https://netadminplus.com
#
# Updates:
# - Auto-cleanup of old data to prevent password mismatch
# - Forces Docker Compose V2 to fix compatibility issues
# - Robust MongoDB keyfile handling
#############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
INSTALL_DIR=$(pwd)
ENV_FILE="$INSTALL_DIR/.env"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
DATA_DIR="$INSTALL_DIR/data"
MONGODB_DATA="$DATA_DIR/mongodb"
UPLOADS_DIR="$DATA_DIR/uploads"
CERTS_DIR="$DATA_DIR/certs"

#############################################################################
# Helper Functions
#############################################################################

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║           🚀 RocketChat One-Click Installer 🚀                ║"
    echo "║                                                                ║"
    echo "║              Created by: Ramtin - NetAdminPlus                ║"
    echo "║           https://netadminplus.com                            ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

print_step() { echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"; }
print_info() { echo -e "${CYAN}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_separator() { echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"; }

ask_question() {
    local question=$1
    local var_name=$2
    local default=$3
    
    if [ -n "$default" ]; then
        echo -e "${MAGENTA}?${NC} $question ${YELLOW}[default: $default]${NC}"
    else
        echo -e "${MAGENTA}?${NC} $question"
    fi
    
    read -r input < /dev/tty
    if [ -z "$input" ] && [ -n "$default" ]; then
        eval "$var_name='$default'"
    else
        eval "$var_name='$input'"
    fi
}

#############################################################################
# Core Checks & Cleanup
#############################################################################

check_root() {
    print_step "Checking root privileges..."
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root or with sudo"
        print_info "Please run: ${YELLOW}sudo $0${NC}"
        exit 1
    fi
    print_success "Running with root privileges"
}

# --- NUCLEAR CLEANUP (Prevent Password Conflicts) ---
perform_cleanup() {
    print_separator
    print_step "Performing Pre-Installation Cleanup..."
    print_warning "This ensures a fresh install by removing old containers and data."
    
    # Stop containers nicely first
    if command -v docker &> /dev/null; then
        print_info "Stopping existing containers..."
        docker compose down -v 2>/dev/null || true
        # Force kill everything else
        docker rm -f $(docker ps -aq) 2>/dev/null || true
        docker network prune -f 2>/dev/null || true
    fi

    # Delete local data to ensure fresh passwords
    print_info "Removing old configuration and data..."
    rm -rf "$DATA_DIR"
    rm -f "$ENV_FILE"
    rm -f "$COMPOSE_FILE"
    
    print_success "Cleanup complete. Ready for fresh install."
}

detect_distro() {
    print_step "Detecting Linux distribution..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
        case $DISTRO in
            ubuntu|debian) PKG_MANAGER="apt" ;;
            centos|rhel|rocky|almalinux)
                PKG_MANAGER="dnf"
                if ! command -v dnf &> /dev/null; then PKG_MANAGER="yum"; fi
                ;;
            *)
                PKG_MANAGER="apt"
                print_warning "Unknown distro: $DISTRO. Defaulting to apt."
                ;;
        esac
        print_success "Detected: $PRETTY_NAME"
    else
        print_error "Cannot detect distribution."
        exit 1
    fi
}

check_system_requirements() {
    print_step "Checking system requirements..."
    local total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    
    if [ "$total_ram_mb" -lt 2048 ]; then
        print_warning "RAM: $total_ram_mb MB detected. Minimum 2GB required."
        ask_question "Continue anyway? (yes/no)" continue_ram "no"
        if [[ ! "$continue_ram" =~ ^[Yy] ]]; then exit 1; fi
    else
        print_success "RAM: OK"
    fi
}

check_docker_hub_access() {
    print_step "Checking Docker Hub accessibility..."
    if timeout 5 curl -sf https://hub.docker.com &> /dev/null; then
        print_success "Docker Hub is accessible"
        DOCKER_REGISTRY_MIRROR=""
    else
        print_warning "Docker Hub blocked or inaccessible."
        ask_question "Do you have a mirror URL? (yes/no)" has_mirror "no"
        if [[ "$has_mirror" =~ ^[Yy] ]]; then
            ask_question "Enter mirror URL:" DOCKER_REGISTRY_MIRROR ""
        fi
    fi
}

#############################################################################
# Installation Functions
#############################################################################

install_dependencies() {
    print_step "Installing system dependencies..."
    if [ "$PKG_MANAGER" = "apt" ]; then
        # || true prevents exit on 403 Forbidden errors
        apt update -qq || true
        apt install -y curl wget git ca-certificates gnupg lsb-release jq bc &> /dev/null
    else
        $PKG_MANAGER install -y curl wget git ca-certificates jq bc &> /dev/null
    fi
    print_success "Dependencies installed"
}

install_docker() {
    print_step "Installing/Updating Docker..."
    
    # Check if Docker Engine is installed
    if command -v docker &> /dev/null; then
        local current_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        print_info "Docker is already installed (version: $current_version)"
    else
        print_info "Docker not found. Installing..."
    fi
    
    case $PKG_MANAGER in
        apt)
            # Clean up old configurations
            rm -f /etc/apt/sources.list.d/docker.list
            rm -f /etc/apt/sources.list.d/docker.sources
            rm -f /etc/apt/keyrings/docker.gpg
            rm -f /etc/apt/keyrings/docker.asc
            
            # Remove old versions
            apt remove -y docker docker-engine docker.io containerd runc docker-compose &> /dev/null || true
            
            # Method 1: Try official repository first
            print_info "Attempting Docker installation from official repository..."
            install -m 0755 -d /etc/apt/keyrings
            
            # Try to add GPG key
            if curl -fsSL https://download.docker.com/linux/$DISTRO/gpg -o /etc/apt/keyrings/docker.asc 2>/dev/null; then
                chmod a+r /etc/apt/keyrings/docker.asc
                cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$DISTRO
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
                # Try to update (with || true to prevent crash on 403 Forbidden)
                apt update -qq || true
                
                # Try install. If this fails (e.g. repo blocked), we go to else block
                if apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | grep -q "Unable to locate"; then
                    print_warning "Official repository blocked/unavailable."
                    print_info "Switching to Ubuntu repository..."
                    
                    # Method 2: Fallback to Ubuntu/Debian Repository
                    # IMPORTANT: We do NOT install 'docker-compose' here (it is too old)
                    apt update -qq || true
                    apt install -y docker.io -qq
                    print_success "Docker Engine installed from OS repository"
                else
                    print_success "Docker installed from Official repository"
                fi
            else
                print_warning "Could not fetch Docker GPG key."
                print_info "Switching to Ubuntu repository..."
                
                # Method 2: Fallback
                apt update -qq || true
                apt install -y docker.io -qq
                print_success "Docker Engine installed from OS repository"
            fi
            ;;
        dnf|yum)
            if ! command -v docker &> /dev/null; then
                $PKG_MANAGER install -y docker &> /dev/null
            fi
            ;;
    esac
    
    # Enable Docker Service
    systemctl start docker
    systemctl enable docker &> /dev/null
    
    # --- CRITICAL FIX: Ensure Docker Compose V2 is installed ---
    print_step "Verifying Docker Compose version..."
    
    # 1. Remove the 'apt' version if it exists (it's likely v1.x and broken)
    if [ "$PKG_MANAGER" = "apt" ]; then
        if dpkg -l | grep -q "docker-compose"; then
             print_info "Removing outdated package version of docker-compose..."
             apt remove -y docker-compose &> /dev/null || true
        fi
    fi
    
    # 2. Force install standalone binary V2 if the plugin isn't working or missing
    # We download v2.24.5 which is known to be stable
    print_info "Installing/Updating Docker Compose Standalone (V2)..."
    rm -f /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    if curl -SL https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose; then
        chmod +x /usr/local/bin/docker-compose
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        print_success "Docker Compose V2 installed successfully"
    else
        print_error "Failed to download Docker Compose. Check internet connection."
        exit 1
    fi

    # Configure Docker registry mirror if provided
    if [ -n "$DOCKER_REGISTRY_MIRROR" ]; then
        print_info "Configuring Docker registry mirror..."
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$DOCKER_REGISTRY_MIRROR"]
}
EOF
        systemctl restart docker
        print_success "Docker registry mirror configured"
    fi
    
    # Final Checks
    if ! command -v docker &> /dev/null; then
        print_error "Docker installation failed"
        exit 1
    fi
    
    # Verify Compose works
    if ! docker-compose version &> /dev/null; then
         print_error "Docker Compose installation failed"
         exit 1
    fi
}

verify_dns() {
    local domain=$1
    print_step "Verifying DNS for $domain..."
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short "$domain" @8.8.8.8 | tail -n1)
    
    if [ -z "$domain_ip" ]; then
        print_error "Domain does not resolve."
        ask_question "Continue anyway? (yes/no)" cont "no"
        if [[ ! "$cont" =~ ^[Yy] ]]; then exit 1; fi
        return 1
    fi
    
    if [ "$server_ip" != "$domain_ip" ]; then
        print_warning "DNS Mismatch: Domain ($domain_ip) != Server ($server_ip)"
        ask_question "Continue anyway? (yes/no)" cont "no"
        if [[ ! "$cont" =~ ^[Yy] ]]; then exit 1; fi
    else
        print_success "DNS Verified ($domain_ip)"
    fi
}

generate_credentials() {
    print_step "Generating secure credentials..."
    MONGO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    MONGO_OPLOG_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    print_success "Credentials generated"
}

create_env_file() {
    print_step "Creating configuration files..."
    cat > "$ENV_FILE" <<EOF
# RocketChat Environment Configuration
# Generated by NetAdminPlus RocketChat Installer
# Date: $(date)

DOMAIN=$DOMAIN
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
MONGO_ROOT_PASSWORD=$MONGO_ROOT_PASSWORD
MONGO_OPLOG_PASSWORD=$MONGO_OPLOG_PASSWORD
ROOT_URL=https://$DOMAIN
PORT=3000
MONGO_URL=mongodb://rocketchat:$MONGO_OPLOG_PASSWORD@mongodb:27017/rocketchat?authSource=admin
MONGO_OPLOG_URL=mongodb://oploguser:$MONGO_OPLOG_PASSWORD@mongodb:27017/local?authSource=admin
EOF
    chmod 600 "$ENV_FILE"
    print_success "Environment file created"
}

create_directories() {
    print_step "Creating data directories..."
    mkdir -p "$MONGODB_DATA" "$UPLOADS_DIR" "$CERTS_DIR"
    
    # Robust Keyfile Creation: Ensure directory exists and no conflict
    print_info "Generating MongoDB keyfile..."
    
    # Remove if it exists as a directory (accidental)
    if [ -d "$MONGODB_DATA/replica.key" ]; then
        rm -rf "$MONGODB_DATA/replica.key"
    fi
    
    # Create the file
    local keyfile="$MONGODB_DATA/replica.key"
    openssl rand -base64 756 > "$keyfile"
    chmod 400 "$keyfile"
    # User 999 is mongo inside container
    chown 999:999 "$keyfile"
    
    chmod 755 "$DATA_DIR"
    print_success "Directories created"
}

create_docker_compose() {
    print_step "Creating Docker Compose file..."
    cat > "$COMPOSE_FILE" <<'EOF'
version: '3.8'

services:
  mongodb:
    image: mongo:6.0
    container_name: rocketchat-mongodb
    restart: unless-stopped
    volumes:
      - ./data/mongodb:/data/db
      - ./data/mongodb/replica.key:/etc/mongo-keyfile:ro
    environment:
      - MONGO_INITDB_ROOT_USERNAME=root
      - MONGO_INITDB_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD}
    command: mongod --oplogSize 128 --replSet rs0 --keyFile /etc/mongo-keyfile
    networks:
      - rocketchat-network
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5

  mongodb-init-replica:
    image: mongo:6.0
    container_name: rocketchat-mongodb-init
    restart: "no"
    depends_on:
      mongodb:
        condition: service_healthy
    environment:
      - MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD}
      - MONGO_OPLOG_PASSWORD=${MONGO_OPLOG_PASSWORD}
    networks:
      - rocketchat-network
    command: >
      mongosh --host mongodb --username root --password ${MONGO_ROOT_PASSWORD} --authenticationDatabase admin --eval "
        rs.initiate({
          _id: 'rs0',
          members: [{ _id: 0, host: 'mongodb:27017' }]
        });
        db = db.getSiblingDB('admin');
        db.createUser({
          user: 'rocketchat',
          pwd: '${MONGO_OPLOG_PASSWORD}',
          roles: [
            { role: 'readWrite', db: 'rocketchat' },
            { role: 'readWrite', db: 'local' }
          ]
        });
        db.createUser({
          user: 'oploguser',
          pwd: '${MONGO_OPLOG_PASSWORD}',
          roles: [
            { role: 'read', db: 'local' }
          ]
        });
      "

  rocketchat:
    image: rocket.chat:latest
    container_name: rocketchat-app
    restart: unless-stopped
    depends_on:
      - mongodb
    environment:
      - ROOT_URL=${ROOT_URL}
      - PORT=${PORT}
      - MONGO_URL=${MONGO_URL}
      - MONGO_OPLOG_URL=${MONGO_OPLOG_URL}
    volumes:
      - ./data/uploads:/app/uploads
    networks:
      - rocketchat-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.rocketchat.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.rocketchat.entrypoints=websecure"
      - "traefik.http.routers.rocketchat.tls.certresolver=letsencrypt"
      - "traefik.http.services.rocketchat.loadbalancer.server.port=${PORT}"

  traefik:
    image: traefik:v2.10
    container_name: rocketchat-traefik
    restart: unless-stopped
    command:
      - "--api.insecure=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=${LETSENCRYPT_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./data/certs:/letsencrypt"
    networks:
      - rocketchat-network

networks:
  rocketchat-network:
    driver: bridge
EOF
    print_success "Docker Compose file created"
}

start_services() {
    print_step "Starting RocketChat services..."
    cd "$INSTALL_DIR"
    
    # Use standalone docker-compose
    DOCKER_COMPOSE_CMD="docker-compose"
    
    print_info "Pulling images..."
    $DOCKER_COMPOSE_CMD pull
    
    print_info "Starting containers..."
    $DOCKER_COMPOSE_CMD up -d
    
    print_success "Services started."
    print_info "Waiting for initialization (approx 1-2 mins)..."
    
    local max_wait=120
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if $DOCKER_COMPOSE_CMD logs rocketchat 2>&1 | grep -q "SERVER RUNNING"; then
            print_success "RocketChat is ready!"
            return 0
        fi
        echo -ne "\rWaiting... ${waited}s/${max_wait}s"
        sleep 5
        waited=$((waited + 5))
    done
    
    echo ""
    print_info "Logs: $DOCKER_COMPOSE_CMD logs -f rocketchat"
}

display_firewall_commands() {
    print_separator
    print_step "Firewall Configuration"
    echo ""
    print_info "Please ensure ports 80 and 443 are open:"
    echo -e "  ${YELLOW}sudo ufw allow 80/tcp${NC}"
    echo -e "  ${YELLOW}sudo ufw allow 443/tcp${NC}"
    print_separator
}

display_final_info() {
    echo ""
    print_separator
    print_success "🎉 RocketChat installation completed! 🎉"
    print_separator
    echo ""
    print_info "URL: https://$DOMAIN"
    print_info "Admin: First registered user becomes admin"
    echo ""
    print_info "Credentials: $ENV_FILE"
    print_info "MongoDB Pass: $MONGO_ROOT_PASSWORD"
    print_separator
    echo ""
}

#############################################################################
# Main Flow
#############################################################################

main() {
    print_banner
    check_root
    
    # 1. Clean up potential conflicts first!
    perform_cleanup
    
    detect_distro
    check_system_requirements
    
    print_separator
    check_docker_hub_access
    
    print_separator
    install_dependencies
    install_docker
    
    print_separator
    print_step "Configuration"
    echo ""
    
    ask_question "Enter domain name:" DOMAIN ""
    while [ -z "$DOMAIN" ]; do
        ask_question "Domain required:" DOMAIN ""
    done
    
    verify_dns "$DOMAIN"
    ask_question "Email for SSL (optional):" LETSENCRYPT_EMAIL ""
    
    print_separator
    generate_credentials
    create_directories
    create_env_file
    create_docker_compose
    
    print_separator
    start_services
    
    display_firewall_commands
    display_final_info
}

# Run main function
main "$@"
