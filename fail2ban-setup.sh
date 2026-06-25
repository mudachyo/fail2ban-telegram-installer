#!/bin/bash

# ============================================
# fail2ban-telegram-installer
# Automated Fail2Ban + Telegram notifications
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Fail2Ban + Telegram Notifications Installer${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# -------------------------------------------
# Step 1: Check if system is Ubuntu
# -------------------------------------------
echo -e "${YELLOW}[1/8] Checking system...${NC}"

if [ ! -f /etc/os-release ]; then
    echo -e "${RED}✗ Cannot detect operating system. /etc/os-release not found.${NC}"
    exit 1
fi

. /etc/os-release

if [ "$ID" != "ubuntu" ]; then
    echo -e "${RED}✗ This script is designed for Ubuntu only. Detected: $ID${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Ubuntu detected ($VERSION_ID)${NC}"
echo ""

# -------------------------------------------
# Step 2: Configure server name (hostname or custom)
# -------------------------------------------
echo -e "${YELLOW}[2/8] Server name configuration...${NC}"

DEFAULT_HOSTNAME=$(hostname)

echo -e "Default hostname: ${CYAN}$DEFAULT_HOSTNAME${NC}"
read -p "Use this name in Telegram notifications? [Y/n]: " USE_DEFAULT

if [[ "$USE_DEFAULT" =~ ^[Nn] ]]; then
    read -p "Enter custom server name: " CUSTOM_HOSTNAME
    if [ -z "$CUSTOM_HOSTNAME" ]; then
        echo -e "${YELLOW}Name is empty, using default hostname.${NC}"
        SERVER_NAME="$DEFAULT_HOSTNAME"
    else
        SERVER_NAME="$CUSTOM_HOSTNAME"
    fi
else
    SERVER_NAME="$DEFAULT_HOSTNAME"
fi

echo -e "${GREEN}✓ Server name set to: $SERVER_NAME${NC}"
echo ""

# -------------------------------------------
# Step 3: Update package list and install fail2ban
# -------------------------------------------
echo -e "${YELLOW}[3/8] Installing Fail2Ban...${NC}"

sudo apt update
sudo apt install -y fail2ban

echo -e "${GREEN}✓ Fail2Ban installed${NC}"
echo ""

# -------------------------------------------
# Step 4: Copy jail.conf to jail.local
# -------------------------------------------
echo -e "${YELLOW}[4/8] Configuring jail.local...${NC}"

if [ -f /etc/fail2ban/jail.local ]; then
    echo -e "${YELLOW}⚠ /etc/fail2ban/jail.local already exists. Creating backup...${NC}"
    sudo cp /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.backup.$(date +%s)"
fi

sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

echo -e "${GREEN}✓ jail.local created${NC}"
echo ""

# -------------------------------------------
# Step 5: Configure jail.local with custom settings
# -------------------------------------------
echo -e "${YELLOW}[5/8] Applying custom Fail2Ban rules...${NC}"

# Comment out default [sshd] section (header + content, but not the next section header)
sudo sed -i -e '/^\[sshd\]/,/^\[/{/^\[/!s/^/#/}' -e '/^\[sshd\]/s/^/#/' /etc/fail2ban/jail.local

# Comment out default [recidive] section (header + content, but not the next section header)
sudo sed -i -e '/^\[recidive\]/,/^\[/{/^\[/!s/^/#/}' -e '/^\[recidive\]/s/^/#/' /etc/fail2ban/jail.local

# Append custom configuration
sudo tee -a /etc/fail2ban/jail.local > /dev/null << 'CUSTOM_JAIL'

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 10800
findtime = 10800
action = iptables-multiport[name=sshd, port=ssh, protocol=tcp]
         telegram

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
filter = recidive
action = iptables-allports[name=recidive]
         telegram
bantime = -1
findtime = 86400
maxretry = 3
CUSTOM_JAIL

echo -e "${GREEN}✓ Custom Fail2Ban rules applied${NC}"
echo ""

# -------------------------------------------
# Step 6: Ask for Telegram bot token and chat ID
# -------------------------------------------
echo -e "${YELLOW}[6/8] Telegram bot configuration...${NC}"

read -p "Enter Telegram Bot TOKEN: " TELEGRAM_TOKEN
while [ -z "$TELEGRAM_TOKEN" ]; do
    echo -e "${RED}Token cannot be empty.${NC}"
    read -p "Enter Telegram Bot TOKEN: " TELEGRAM_TOKEN
done

read -p "Enter Telegram CHAT_ID: " TELEGRAM_CHAT_ID
while [ -z "$TELEGRAM_CHAT_ID" ]; do
    echo -e "${RED}CHAT_ID cannot be empty.${NC}"
    read -p "Enter Telegram CHAT_ID: " TELEGRAM_CHAT_ID
done

echo -e "${GREEN}✓ Telegram credentials received${NC}"
echo ""

# -------------------------------------------
# Step 7: Create notification script
# -------------------------------------------
echo -e "${YELLOW}[7/8] Creating Telegram notification script...${NC}"

# Determine which hostname to use in the script
if [ "$SERVER_NAME" = "$DEFAULT_HOSTNAME" ]; then
    # Use dynamic hostname (no override)
    HOSTNAME_LINE='HOSTNAME=$(hostname)'
else
    # Use custom name
    HOSTNAME_LINE="HOSTNAME=\"$SERVER_NAME\""
fi

sudo tee /usr/local/bin/fail2ban-telegram.sh > /dev/null << SCRIPT_EOF
#!/bin/bash

TOKEN="${TELEGRAM_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"

ACTION="\$1"
IP="\$2"
JAIL="\$3"

${HOSTNAME_LINE}
DATE=\$(date '+%d.%m.%Y %H:%M:%S')

if [ "\$ACTION" = "ban" ]; then
    ICON="🚫"
    STATUS="Заблокирован IP"
else
    ICON="✅"
    STATUS="Разблокирован IP"
fi

MESSAGE="\$ICON <b>Fail2Ban</b>
<b>Статус:</b> \$STATUS

🖥 <b>Сервер:</b> <code>\$HOSTNAME</code>
📦 <b>Jail:</b> <code>\$JAIL</code>
🌐 <b>IP:</b> <code>\$IP</code>
🕒 <b>Время:</b> <code>\$DATE</code>"

curl -s -X POST "https://api.telegram.org/bot\${TOKEN}/sendMessage" \
    -d chat_id="\${CHAT_ID}" \
    -d parse_mode="HTML" \
    --data-urlencode text="\${MESSAGE}" >/dev/null
SCRIPT_EOF

sudo chmod +x /usr/local/bin/fail2ban-telegram.sh

echo -e "${GREEN}✓ Notification script created at /usr/local/bin/fail2ban-telegram.sh${NC}"
echo ""

# -------------------------------------------
# Step 8: Create action file
# -------------------------------------------
echo -e "${YELLOW}[8/8] Creating Fail2Ban action configuration...${NC}"

sudo tee /etc/fail2ban/action.d/telegram.conf > /dev/null << 'ACTION_CONF'
[Definition]
actionstart =
actionstop =
actioncheck =

actionban = /usr/local/bin/fail2ban-telegram.sh ban <ip> <name>
actionunban = /usr/local/bin/fail2ban-telegram.sh unban <ip> <name>
ACTION_CONF

echo -e "${GREEN}✓ Action configuration created at /etc/fail2ban/action.d/telegram.conf${NC}"
echo ""

# -------------------------------------------
# Restart fail2ban
# -------------------------------------------
echo -e "${YELLOW}Restarting Fail2Ban service...${NC}"
sudo systemctl restart fail2ban

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  Server name:     ${CYAN}$SERVER_NAME${NC}"
echo -e "  Fail2Ban:        ${GREEN}✓${NC}"
echo -e "  Telegram script: ${GREEN}✓${NC}"
echo ""
echo -e "To check Fail2Ban status: ${CYAN}sudo fail2ban-client status${NC}"
echo ""
