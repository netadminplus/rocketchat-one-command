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
read -p "1. Enter your Domain or IP (e.g. chat.mydomain.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: Domain is required.${NC}"
    exit 1
fi

# Question 2: Port
read -p "2. Server Port (default: 3000): " PORT
PORT=${PORT:-3000}

# Question 3: Version
read -p "3. Rocket.Chat Version (default: latest): " RELEASE
RELEASE=${RELEASE:-latest}

# Question 4: Email
read -p "4. Email for SSL/Alerts (optional, press Enter to skip): " EMAIL

# Question 5: Docker Mirror
echo ""
echo "    If Docker Hub is blocked in your region, enter a mirror URL."
read -p "5. Docker Mirror URL (default: None, press Enter to skip): " DOCKER_MIRROR

# --------------------------------------------------
# 2. Check DNS
# --------------------------------------------------
echo -e "\n### Checking DNS Resolution ###"
PUBLIC_IP=$(curl -s ifconfig.me)
echo "    Your Public IP seems to be: $PUBLIC_IP"
echo "    Checking if '$DOMAIN' points to '$PUBLIC_IP'..."

if command -v host &> /dev/null; then
    DOMAIN_IP=$(host $DOMAIN | grep "has address" | head -n 1 | awk '{print $4}')
elif command -v getent &> /dev/null; then
    DOMAIN_IP=$(getent hosts $DOMAIN | awk '{print $1}')
else
    echo "    Warning: Could not verify DNS (missing host/getent). Skipping..."
fi

if [ "$DOMAIN_IP" == "$PUBLIC_IP" ]; then
    echo -e "    ${GREEN}OK: DNS verified! ($DOMAIN -> $PUBLIC_IP)${NC}"
else
    echo -e "    ${YELLOW}WARNING: DNS mismatch or check failed.${NC}"
    echo "    Expected: $PUBLIC_IP"
    echo "    Got:      $DOMAIN_IP"
    echo "    Please ensure your DNS A record is set correctly."
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

# Ensure Docker Compose is available (plugin or standalone)
if ! docker compose version &> /dev/null; then
     echo -e "    ${YELLOW}Docker Compose plugin not found. Attempting to install plugin...${NC}"
     apt-get update && apt-get install -y docker-compose-plugin
fi

# --------------------------------------------------
# 4. Download Template (CRITICAL STEP FOR ONE-CLICK)
# --------------------------------------------------
# This step fetches the template because 'curl | bash' does not download repo files.
echo -e "\n### Downloading Configuration Template ###"
TEMPLATE_URL="https://raw.githubusercontent.com/netadminplus/rocketchat-one-command/main/docker-compose.yml.template"

if curl -s -f -O "$TEMPLATE_URL"; then
    echo -e "    ${GREEN}OK: Template downloaded successfully.${NC}"
else
    echo -e "    ${RED}ERROR: Failed to download docker-compose.yml.template from GitHub.${NC}"
    echo "    Please check your internet connection or the repository URL."
    exit 1
fi

# --------------------------------------------------
# 5. Generate Configuration
# --------------------------------------------------
echo -e "\n### Generating Configuration ###"

if [ ! -f "docker-compose.yml.template" ]; then
    echo -e "    ${RED}ERROR: docker-compose.yml.template not found.${NC}" 
    exit 1
fi

# Create .env file or export variables for substitution
# We will use simple sed replacement to create the final docker-compose.yml
cp docker-compose.yml.template docker-compose.yml

# Determine Root URL
ROOT_URL="http://$DOMAIN:$PORT"
if [ "$PORT" == "443" ] || [ "$PORT" == "80" ]; then
    ROOT_URL="https://$DOMAIN"
fi

# Replace variables in docker-compose.yml
# NOTE: Depending on your OS, sed -i might need an empty string argument for backups
sed -i "s|\${RELEASE}|$RELEASE|g" docker-compose.yml
sed -i "s|\${ROOT_URL}|$ROOT_URL|g" docker-compose.yml
sed -i "s|\${PORT}|$PORT|g" docker-compose.yml

echo -e "    ${GREEN}OK: Configuration generated (docker-compose.yml).${NC}"

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
