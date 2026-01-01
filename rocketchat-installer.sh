#!/bin/bash

# ==================================================
#       Rocket.Chat One-Click Installer
# ==================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "\n${GREEN}=================================================="
echo -e "       Rocket.Chat One-Click Installer            "
echo -e "==================================================${NC}\n"

# --------------------------------------------------
# 1. Gather Information
# --------------------------------------------------
echo "    We need to gather some information before we start."
echo "    Please answer the following questions."
echo ""

# Question 1: Domain
read -p "1. Enter your Domain or IP (e.g. chat.mydomain.com): " DOMAIN < /dev/tty
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: Domain is required.${NC}"
    exit 1
fi

# Question 2: Port
read -p "2. Server Port (default: 3000): " PORT < /dev/tty
PORT=${PORT:-3000}

# Question 3: Version
read -p "3. Rocket.Chat Version (default: latest): " RELEASE < /dev/tty
RELEASE=${RELEASE:-latest}

# Question 4: Email
read -p "4. Email for SSL/Alerts (optional, press Enter to skip): " EMAIL < /dev/tty

# Question 5: Docker Mirror
echo ""
echo "    If Docker Hub is blocked in your region, enter a mirror URL."
read -p "5. Docker Mirror URL (default: None, press Enter to skip): " DOCKER_MIRROR < /dev/tty

# --------------------------------------------------
# 2. Check DNS
# --------------------------------------------------
echo -e "\n### Checking DNS Resolution ###"

# Try getting IP from ipify, fallback to ifconfig.me. 
# -s = silent, --max-time = fail fast if blocked
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me/ip)

# Basic validation to ensure we got an IP and not HTML garbage
if [[ ! "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "    ${YELLOW}Warning: Could not detect Public IP (service blocked or unreachable). Skipping DNS check.${NC}"
else
    echo "    Your Public IP seems to be: $PUBLIC_IP"
    echo "    Checking if '$DOMAIN' points to '$PUBLIC_IP'..."

    if command -v host &> /dev/null; then
        DOMAIN_IP=$(host $DOMAIN | grep "has address" | head -n 1 | awk '{print $4}')
    elif command -v getent &> /dev/null; then
        DOMAIN_IP=$(getent hosts $DOMAIN | awk '{print $1}')
    fi

    if [ "$DOMAIN_IP" == "$PUBLIC_IP" ]; then
        echo -e "    ${GREEN}OK: DNS verified! ($DOMAIN -> $PUBLIC_IP)${NC}"
    elif [ -z "$DOMAIN_IP" ]; then
        echo -e "    ${YELLOW}Warning: Could not resolve domain locally. Skipping check.${NC}"
    else
        echo -e "    ${YELLOW}WARNING: DNS mismatch.${NC}"
        echo "    Expected: $PUBLIC_IP"
        echo "    Got:      $DOMAIN_IP"
    fi
fi

# --------------------------------------------------
# 3. Check/Install Docker
# --------------------------------------------------
echo -e "\n### Preparing Environment ###\n"
echo "==> Checking Docker Installation..."

if ! command -v docker &> /dev/null; then
    echo "    Docker not found. Installing..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    
    if [ ! -z "$DOCKER_MIRROR" ]; then
        echo "    Using Docker Mirror: $DOCKER_MIRROR"
        sh get-docker.sh --mirror "$DOCKER_MIRROR"
    else
        sh get-docker.sh
    fi
    rm get-docker.sh
else
    DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
    echo -e "    ${GREEN}OK: Docker already installed ($DOCKER_VER)${NC}"
fi

# Ensure Docker Compose is available
if ! docker compose version &> /dev/null; then
     echo -e "    ${YELLOW}Docker Compose plugin not found. Attempting to install plugin...${NC}"
     apt-get update && apt-get install -y docker-compose-plugin
fi

# --------------------------------------------------
# 4. Download Template
# --------------------------------------------------
echo -e "\n### Downloading Configuration Template ###"
TEMPLATE_URL="https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/docker-compose.yml.template"

# Always remove old template to ensure we get a fresh one
rm -f docker-compose.yml.template

if curl -s -f -O "$TEMPLATE_URL"; then
    echo -e "    ${GREEN}OK: Template downloaded successfully.${NC}"
else
    echo -e "    ${RED}ERROR: Failed to download docker-compose.yml.template from GitHub.${NC}"
    exit 1
fi

# --------------------------------------------------
# 5. Generate Configuration (.env)
# --------------------------------------------------
echo -e "\n### Generating Configuration ###"

# Determine Root URL
ROOT_URL="http://$DOMAIN:$PORT"
if [ "$PORT" == "443" ] || [ "$PORT" == "80" ]; then
    ROOT_URL="https://$DOMAIN"
fi

# Create .env file. Docker Compose automatically reads this.
# This prevents YAML syntax errors caused by sed.
echo "RELEASE=$RELEASE" > .env
echo "ROOT_URL=$ROOT_URL" >> .env
echo "PORT=$PORT" >> .env
echo "MONGO_URL=mongodb://mongo:27017/rocketchat?replicaSet=rs0&directConnection=true" >> .env
echo "MONGO_OPLOG_URL=mongodb://mongo:27017/local?replicaSet=rs0&directConnection=true" >> .env

# Simply copy the template to the actual file
cp docker-compose.yml.template docker-compose.yml

echo -e "    ${GREEN}OK: Configuration generated (.env and docker-compose.yml).${NC}"

# --------------------------------------------------
# 6. Start Services
# --------------------------------------------------
echo -e "\n### Starting Rocket.Chat ###"
docker compose up -d

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}=================================================="
    echo -e "   INSTALLATION SUCCESSFUL!"
    echo -e "==================================================${NC}"
    echo -e "    Rocket.Chat is running at: $ROOT_URL"
    echo -e "    To stop: docker compose down"
    echo -e "    To logs: docker compose logs -f"
else
    echo -e "\n${RED}ERROR: Failed to start containers.${NC}"
    exit 1
fi
