#!/bin/bash

#############################################################################
# RocketChat One-Click Installer
# 
# Created by: Ramtin - NetAdminPlus
# Website: https://netadminplus.com
# YouTube: https://youtube.com/@netadminplus
# Instagram: https://instagram.com/netadminplus
#
# Description: Automated RocketChat deployment with Docker, SSL, and 
#              Iranian mirror support
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
    echo "║           YouTube: @netadminplus                              ║"
    echo "║           Instagram: @netadminplus                            ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

print_step() {
    echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
}

ask_question() {
    local question=$1
    local var_name=$2
    local default=$3
    
    if [ -n "$default" ]; then
        echo -e "${MAGENTA}?${NC} $question ${YELLOW}[default: $default]${NC}"
    else
        echo -e "${MAGENTA}?${NC} $question"
    fi
    
    # Read from terminal directly, not from stdin
    read -r input < /dev/tty
    
    if [ -z "$input" ] && [ -n "$default" ]; then
        eval "$var_name='$default'"
    else
        eval "$var_name='$input'"
    fi
}

#############################################################################
# Check Functions
#############################################################################

check_root() {
    print_step "Checking root privileges..."
    
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root or with sudo"
        echo ""
        print_info "Please run: ${YELLOW}sudo $0${NC}"
        exit 1
    fi
    
    print_success "Running with root privileges"
}

detect_distro() {
    print_step "Detecting Linux distribution..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
        
        case $DISTRO in
            ubuntu|debian)
                PKG_MANAGER="apt"
                print_success "Detected: $PRETTY_NAME"
                ;;
            centos|rhel|rocky|almalinux)
                PKG_MANAGER="dnf"
                if ! command -v dnf &> /dev/null; then
                    PKG_MANAGER="yum"
                fi
                print_success "Detected: $PRETTY_NAME"
                ;;
            *)
                print_warning "Unknown distribution: $DISTRO"
                print_info "Attempting to continue, but issues may occur..."
                if command -v apt &> /dev/null; then
                    PKG_MANAGER="apt"
                elif command -v dnf &> /dev/null; then
                    PKG_MANAGER="dnf"
                elif command -v yum &> /dev/null; then
                    PKG_MANAGER="yum"
                else
                    print_error "Cannot determine package manager"
                    exit 1
                fi
                ;;
        esac
    else
        print_error "Cannot detect distribution. /etc/os-release not found"
        exit 1
    fi
}

check_system_requirements() {
    print_step "Checking system requirements..."
    
    # Check RAM (in MB for better accuracy)
    local total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    local total_ram_gb=$(echo "scale=1; $total_ram_mb/1024" | bc)
    
    if [ "$total_ram_mb" -lt 2048 ]; then
        print_warning "RAM: ${total_ram_gb}GB detected (Minimum 2GB required, 4GB recommended)"
        print_info "Your server may experience performance issues or instability"
        echo ""
        ask_question "Do you want to continue anyway? (yes/no)" continue_with_low_ram "no"
        
        if [[ ! "$continue_with_low_ram" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            print_error "Installation cancelled due to insufficient RAM"
            exit 1
        fi
        print_warning "Continuing with low RAM - monitor your system closely"
    else
        print_success "RAM: ${total_ram_gb}GB"
    fi
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        print_warning "CPU: ${cpu_cores} core(s) (2+ cores recommended for better performance)"
    else
        print_success "CPU: ${cpu_cores} core(s)"
    fi
    
    # Check disk space (need at least 20GB)
    local disk_space=$(df -BG "$INSTALL_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$disk_space" -lt 20 ]; then
        print_warning "Disk space: ${disk_space}GB available (Minimum 20GB recommended)"
        print_info "You may run out of space as your RocketChat database grows"
        echo ""
        ask_question "Do you want to continue anyway? (yes/no)" continue_with_low_disk "no"
        
        if [[ ! "$continue_with_low_disk" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            print_error "Installation cancelled due to insufficient disk space"
            exit 1
        fi
        print_warning "Continuing with limited disk space - monitor usage regularly"
    else
        print_success "Disk space: ${disk_space}GB available"
    fi
}

check_docker_hub_access() {
    print_step "Checking Docker Hub accessibility..."
    
    if timeout 5 curl -sf https://hub.docker.com &> /dev/null; then
        print_success "Docker Hub is accessible"
        DOCKER_REGISTRY_MIRROR=""
        return 0
    else
        print_warning "Docker Hub is not accessible or blocked"
        echo ""
        print_info "You may need a Docker registry mirror for pulling images"
        echo ""
        
        ask_question "Do you have a Docker registry mirror? (yes/no)" has_mirror "no"
        
        if [[ "$has_mirror" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            ask_question "Enter your Docker registry mirror URL:" DOCKER_REGISTRY_MIRROR ""
            
            if [ -n "$DOCKER_REGISTRY_MIRROR" ]; then
                print_success "Will use mirror: $DOCKER_REGISTRY_MIRROR"
            fi
        else
            print_warning "Continuing without mirror. Image pulls may fail."
            DOCKER_REGISTRY_MIRROR=""
        fi
        
        return 1
    fi
}

#############################################################################
# Installation Functions
#############################################################################

install_dependencies() {
    print_step "Installing system dependencies..."
    
    case $PKG_MANAGER in
        apt)
            print_info "Updating package lists..."
            # Added || true to prevent script exit on 403 Forbidden errors
            apt update -qq || true
            
            print_info "Installing dependencies..."
            apt install -y curl wget git ca-certificates gnupg lsb-release jq bc &> /dev/null
            ;;
        dnf|yum)
            print_info "Installing dependencies..."
            $PKG_MANAGER install -y curl wget git ca-certificates jq bc &> /dev/null
            ;;
    esac
    
    print_success "Dependencies installed"
}

install_docker() {
    print_step "Installing/Updating Docker..."
    
    if command -v docker &> /dev/null; then
        local current_version=$(docker --version | awk '{print $3}' | sed 's/,//')
        print_info "Docker is already installed (version: $current_version)"
        print_info "Updating Docker to latest version..."
    else
        print_info "Docker not found. Installing..."
    fi
    
    case $PKG_MANAGER in
        apt)
            # Clean up any existing Docker repository configurations first
            rm -f /etc/apt/sources.list.d/docker.list
            rm -f /etc/apt/sources.list.d/docker.sources
            rm -f /etc/apt/keyrings/docker.gpg
            rm -f /etc/apt/keyrings/docker.asc
            
            # Remove old versions
            apt remove -y docker docker-engine docker.io containerd runc &> /dev/null || true
            
            # Method 1: Try official repository first
            print_info "Attempting Docker installation from official repository..."
            
            # Add Docker's official GPG key
            install -m 0755 -d /etc/apt/keyrings
            
            if curl -fsSL https://download.docker.com/linux/$DISTRO/gpg -o /etc/apt/keyrings/docker.asc 2>/dev/null; then
                chmod a+r /etc/apt/keyrings/docker.asc
                
                # Add Docker repository using new format
                cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$DISTRO
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
                
                # Try to update and install
                apt update -qq 2>&1 | grep -v "Failed to fetch" | grep -v "403" || true
                
                if apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | grep -q "Unable to locate"; then
                    print_warning "Official repository blocked or unavailable"
                    print_info "Trying alternative installation method..."
                    
                    # Clean up failed attempt
                    rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
                    
                    # Method 2: Install from Ubuntu repository
                    print_info "Installing Docker from Ubuntu repository..."
                    apt update -qq || true
                    apt install -y docker.io docker-compose -qq
                    
                    # Create docker compose plugin symlink for compatibility
                    mkdir -p /usr/local/lib/docker/cli-plugins
                    ln -sf /usr/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose 2>/dev/null || true
                    
                    print_success "Docker installed from Ubuntu repository"
                else
                    print_success "Docker installed from official repository"
                fi
            else
                print_warning "Cannot access Docker official repository (possibly blocked)"
                print_info "Installing Docker from Ubuntu repository..."
                
                # Clean up
                rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/keyrings/docker.asc
                
                apt update -qq || true
                apt install -y docker.io docker-compose -qq
                
                # Create docker compose plugin symlink for compatibility
                mkdir -p /usr/local/lib/docker/cli-plugins
                ln -sf /usr/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose 2>/dev/null || true
                
                print_success "Docker installed from Ubuntu repository"
            fi
            ;;
        dnf|yum)
            # Remove old versions
            $PKG_MANAGER remove -y docker docker-client docker-client-latest docker-common docker-latest \
                docker-latest-logrotate docker-logrotate docker-engine &> /dev/null || true
            
            print_info "Attempting Docker installation from official repository..."
            
            # Add Docker repository
            if $PKG_MANAGER install -y yum-utils &> /dev/null && \
               yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &> /dev/null; then
                
                # Try to install
                if $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &> /dev/null; then
                    print_success "Docker installed from official repository"
                else
                    print_warning "Official repository blocked or unavailable"
                    print_info "Installing Docker from system repository..."
                    
                    $PKG_MANAGER install -y docker docker-compose &> /dev/null
                    print_success "Docker installed from system repository"
                fi
            else
                print_warning "Cannot access Docker official repository"
                print_info "Installing Docker from system repository..."
                
                $PKG_MANAGER install -y docker docker-compose &> /dev/null
                print_success "Docker installed from system repository"
            fi
            ;;
    esac
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker &> /dev/null
    
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
    
    # Verify installation
    if ! command -v docker &> /dev/null; then
        print_error "Docker installation failed"
        exit 1
    fi
    
    local new_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    print_success "Docker installed/updated (version: $new_version)"
    
    # Check for docker compose (plugin or standalone)
    if docker compose version &> /dev/null; then
        print_success "Docker Compose (plugin) is available"
    elif command -v docker-compose &> /dev/null; then
        print_success "Docker Compose (standalone) is available"
        print_info "Note: Using 'docker-compose' command instead of 'docker compose'"
    else
        print_error "Docker Compose is not available"
        exit 1
    fi
}

verify_dns() {
    local domain=$1
    
    print_step "Verifying DNS configuration for $domain..."
    
    print_info "Getting server's public IP address..."
    local server_ip=$(curl -s https://api.ipify.org)
    
    if [ -z "$server_ip" ]; then
        print_error "Could not determine server's public IP"
        return 1
    fi
    
    print_info "Server IP: $server_ip"
    
    print_info "Checking DNS resolution..."
    local domain_ip=$(dig +short "$domain" @8.8.8.8 | tail -n1)
    
    if [ -z "$domain_ip" ]; then
        print_error "Domain $domain does not resolve to any IP"
        print_info "Please ensure your domain's A record points to: $server_ip"
        echo ""
        ask_question "Do you want to continue anyway? (yes/no)" continue_anyway "no"
        
        if [[ ! "$continue_anyway" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            print_error "Installation cancelled. Please configure DNS and try again."
            exit 1
        fi
        
        return 1
    fi
    
    print_info "Domain resolves to: $domain_ip"
    
    if [ "$server_ip" != "$domain_ip" ]; then
        print_warning "DNS mismatch!"
        print_info "Server IP: $server_ip"
        print_info "Domain IP: $domain_ip"
        echo ""
        print_info "Please update your domain's A record to point to: $server_ip"
        echo ""
        ask_question "Do you want to continue anyway? (yes/no)" continue_anyway "no"
        
        if [[ ! "$continue_anyway" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            print_error "Installation cancelled. Please configure DNS and try again."
            exit 1
        fi
        
        return 1
    fi
    
    print_success "DNS configuration verified successfully"
    return 0
}

generate_credentials() {
    print_step "Generating secure credentials..."
    
    MONGO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    MONGO_OPLOG_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    print_success "Credentials generated"
}

create_env_file() {
    print_step "Creating environment file..."
    
    cat > "$ENV_FILE" <<EOF
# RocketChat Environment Configuration
# Generated by NetAdminPlus RocketChat Installer
# Date: $(date)

# Domain Configuration
DOMAIN=$DOMAIN
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL

# MongoDB Configuration
MONGO_ROOT_PASSWORD=$MONGO_ROOT_PASSWORD
MONGO_OPLOG_PASSWORD=$MONGO_OPLOG_PASSWORD

# RocketChat Configuration
ROOT_URL=https://$DOMAIN
PORT=3000

# MongoDB Connection
MONGO_URL=mongodb://rocketchat:$MONGO_OPLOG_PASSWORD@mongodb:27017/rocketchat?authSource=admin
MONGO_OPLOG_URL=mongodb://oploguser:$MONGO_OPLOG_PASSWORD@mongodb:27017/local?authSource=admin
EOF
    
    chmod 600 "$ENV_FILE"
    print_success "Environment file created: $ENV_FILE"
}

create_directories() {
    print_step "Creating data directories..."
    
    mkdir -p "$MONGODB_DATA"
    mkdir -p "$UPLOADS_DIR"
    mkdir -p "$CERTS_DIR"
    
    # Create MongoDB keyfile for replica set authentication
    print_info "Generating MongoDB keyfile..."
    local keyfile="$MONGODB_DATA/replica.key"
    openssl rand -base64 756 > "$keyfile"
    chmod 400 "$keyfile"
    # Ensure user 999 (mongo) can read the file
    chown 999:999 "$keyfile"
    
    chmod 755 "$DATA_DIR"
    
    print_success "Data directories created"
}

create_docker_compose() {
    print_step "Creating Docker Compose configuration..."
    
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
    
    print_success "Docker Compose file created: $COMPOSE_FILE"
}

create_directories() {
    print_step "Creating data directories..."
    
    mkdir -p "$MONGODB_DATA"
    mkdir -p "$UPLOADS_DIR"
    mkdir -p "$CERTS_DIR"
    
    # Create MongoDB keyfile for replica set authentication
    print_info "Generating MongoDB keyfile..."
    local keyfile="$MONGODB_DATA/replica.key"
    openssl rand -base64 756 > "$keyfile"
    chmod 400 "$keyfile"
    # Ensure user 999 (mongo) can read the file
    chown 999:999 "$keyfile"
    
    chmod 755 "$DATA_DIR"
    
    print_success "Data directories created"
}

start_services() {
    print_step "Starting RocketChat services..."
    
    cd "$INSTALL_DIR"
    
    # Detect docker compose command
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        print_error "Docker Compose not found"
        exit 1
    fi
    
    print_info "Pulling Docker images... (this may take a few minutes)"
    $DOCKER_COMPOSE_CMD pull
    
    print_info "Starting containers..."
    $DOCKER_COMPOSE_CMD up -d
    
    print_success "Services started successfully"
    
    print_info "Waiting for RocketChat to initialize... (this may take 1-2 minutes)"
    
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
    print_warning "RocketChat initialization is taking longer than expected"
    print_info "You can check logs with: ${YELLOW}$DOCKER_COMPOSE_CMD logs -f rocketchat${NC}"
}

display_firewall_commands() {
    print_separator
    print_step "Firewall Configuration"
    echo ""
    print_info "Please ensure ports 80 and 443 are open in your firewall:"
    echo ""
    
    # UFW commands
    print_info "${CYAN}For UFW:${NC}"
    echo -e "  ${YELLOW}sudo ufw allow 80/tcp${NC}"
    echo -e "  ${YELLOW}sudo ufw allow 443/tcp${NC}"
    echo -e "  ${YELLOW}sudo ufw reload${NC}"
    echo ""
    
    # Firewalld commands
    print_info "${CYAN}For firewalld:${NC}"
    echo -e "  ${YELLOW}sudo firewall-cmd --permanent --add-service=http${NC}"
    echo -e "  ${YELLOW}sudo firewall-cmd --permanent --add-service=https${NC}"
    echo -e "  ${YELLOW}sudo firewall-cmd --reload${NC}"
    echo ""
    
    # iptables commands
    print_info "${CYAN}For iptables:${NC}"
    echo -e "  ${YELLOW}sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT${NC}"
    echo -e "  ${YELLOW}sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT${NC}"
    echo -e "  ${YELLOW}sudo iptables-save > /etc/iptables/rules.v4${NC}"
    echo ""
    
    print_separator
}

display_final_info() {
    echo ""
    print_separator
    print_success "🎉 RocketChat installation completed successfully! 🎉"
    print_separator
    echo ""
    
    # Detect docker compose command
    if docker compose version &> /dev/null; then
        local dc_cmd="docker compose"
    else
        local dc_cmd="docker-compose"
    fi
    
    print_info "${CYAN}Access Information:${NC}"
    echo -e "  ${GREEN}URL:${NC} https://$DOMAIN"
    echo -e "  ${GREEN}First user to register becomes admin${NC}"
    echo ""
    
    print_info "${CYAN}Credentials Location:${NC}"
    echo -e "  ${GREEN}File:${NC} $ENV_FILE"
    echo -e "  ${GREEN}MongoDB Root Password:${NC} $MONGO_ROOT_PASSWORD"
    echo ""
    
    print_info "${CYAN}Installation Directory:${NC}"
    echo -e "  ${GREEN}Location:${NC} $INSTALL_DIR"
    echo -e "  ${GREEN}Data:${NC} $DATA_DIR"
    echo ""
    
    print_info "${CYAN}Useful Commands:${NC}"
    echo -e "  ${YELLOW}View logs:${NC}         cd $INSTALL_DIR && $dc_cmd logs -f"
    echo -e "  ${YELLOW}Stop services:${NC}     cd $INSTALL_DIR && $dc_cmd stop"
    echo -e "  ${YELLOW}Start services:${NC}    cd $INSTALL_DIR && $dc_cmd start"
    echo -e "  ${YELLOW}Restart services:${NC}  cd $INSTALL_DIR && $dc_cmd restart"
    echo -e "  ${YELLOW}View status:${NC}       cd $INSTALL_DIR && $dc_cmd ps"
    echo ""
    
    print_separator
    print_info "${MAGENTA}Created by Ramtin - NetAdminPlus${NC}"
    echo -e "  ${CYAN}Website:${NC}   https://netadminplus.com"
    echo -e "  ${CYAN}YouTube:${NC}   https://youtube.com/@netadminplus"
    echo -e "  ${CYAN}Instagram:${NC} https://instagram.com/netadminplus"
    print_separator
    echo ""
}

#############################################################################
# Main Installation Flow
#############################################################################

main() {
    print_banner
    
    # Pre-flight checks
    check_root
    detect_distro
    check_system_requirements
    
    print_separator
    
    # Docker Hub check
    check_docker_hub_access
    
    print_separator
    
    # Install dependencies and Docker
    install_dependencies
    install_docker
    
    print_separator
    
    # Get user input
    echo ""
    print_step "Configuration Setup"
    echo ""
    
    ask_question "Enter your domain name (e.g., chat.example.com):" DOMAIN ""
    
    while [ -z "$DOMAIN" ]; do
        print_error "Domain name cannot be empty"
        ask_question "Enter your domain name (e.g., chat.example.com):" DOMAIN ""
    done
    
    echo ""
    verify_dns "$DOMAIN"
    
    echo ""
    ask_question "Enter email for Let's Encrypt notifications (optional, press Enter to skip):" LETSENCRYPT_EMAIL ""
    
    print_separator
    
    # Generate configuration
    generate_credentials
    create_directories
    create_env_file
    create_docker_compose
    
    print_separator
    
    # Start services
    start_services
    
    print_separator
    
    # Display firewall info
    display_firewall_commands
    
    # Display final information
    display_final_info
    
    print_success "Installation complete! Enjoy your RocketChat server! 🚀"
    echo ""
}

# Run main function
main "$@"
