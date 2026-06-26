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
echo -e "${YELLOW}[1/10] Checking system...${NC}"

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
# Step 2: Check if Fail2Ban is already installed
# -------------------------------------------
echo -e "${YELLOW}[2/10] Checking if Fail2Ban is already installed...${NC}"

NEED_RESTORE=false

if command -v fail2ban-client &> /dev/null; then
    echo -e "${GREEN}✓ Fail2Ban is already installed${NC}"
    echo ""
    echo -e "${YELLOW}Fail2Ban is already installed on this system.${NC}"
    read -p "Do you want to reinstall it with Telegram notifications? [y/N]: " REINSTALL

    if [[ "$REINSTALL" =~ ^[Yy] ]]; then
        echo ""
        echo -e "${YELLOW}→ Backing up banned IPs...${NC}"

        # Backup banned IPs
        if sudo systemctl is-active --quiet fail2ban 2>/dev/null; then
            for jail in $(sudo fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:\s*//p' | tr ',' ' '); do
                echo "[$jail]"
                sudo fail2ban-client status "$jail" 2>/dev/null | sed -n 's/.*Banned IP list:\s*//p'
            done > banned_ips.txt
            echo -e "${GREEN}✓ Banned IPs saved to banned_ips.txt${NC}"
        else
            echo -e "${YELLOW}⚠ Fail2Ban service is not running. Starting it to backup IPs...${NC}"
            sudo systemctl start fail2ban 2>/dev/null || true
            sleep 1
            for jail in $(sudo fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:\s*//p' | tr ',' ' '); do
                echo "[$jail]"
                sudo fail2ban-client status "$jail" 2>/dev/null | sed -n 's/.*Banned IP list:\s*//p'
            done > banned_ips.txt
            echo -e "${GREEN}✓ Banned IPs saved to banned_ips.txt${NC}"
        fi

        # Stop fail2ban
        echo -e "${YELLOW}→ Stopping Fail2Ban service...${NC}"
        sudo systemctl stop fail2ban 2>/dev/null || true

        # Remove fail2ban
        echo -e "${YELLOW}→ Removing existing Fail2Ban installation...${NC}"
        sudo apt remove --purge -y fail2ban

        # Remove custom files
        echo -e "${YELLOW}→ Removing custom notification files...${NC}"
        sudo rm -f /usr/local/bin/fail2ban-telegram.sh
        sudo rm -f /etc/fail2ban/action.d/telegram.conf

        echo -e "${GREEN}✓ Old installation removed. Proceeding with fresh install...${NC}"
        NEED_RESTORE=true
    else
        echo -e "${YELLOW}Installation cancelled by user.${NC}"
        exit 0
    fi
else
    echo -e "${GREEN}✓ Fresh installation detected${NC}"
fi
echo ""

# -------------------------------------------
# Step 3: Configure server name (hostname or custom)
# -------------------------------------------
echo -e "${YELLOW}[3/10] Server name configuration...${NC}"

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
# Step 4: Update package list and install fail2ban
# -------------------------------------------
echo -e "${YELLOW}[4/10] Installing Fail2Ban...${NC}"

sudo apt update
sudo apt install -y fail2ban

echo -e "${GREEN}✓ Fail2Ban installed${NC}"
echo ""

# -------------------------------------------
# Step 5: Copy jail.conf to jail.local
# -------------------------------------------
echo -e "${YELLOW}[5/10] Configuring jail.local...${NC}"

if [ -f /etc/fail2ban/jail.local ]; then
    echo -e "${YELLOW}⚠ /etc/fail2ban/jail.local already exists. Creating backup...${NC}"
    sudo cp /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.backup.$(date +%s)"
fi

sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

echo -e "${GREEN}✓ jail.local created${NC}"
echo ""

# -------------------------------------------
# Step 6: Configure jail.local with custom settings
# -------------------------------------------
echo -e "${YELLOW}[6/10] Applying custom Fail2Ban rules...${NC}"

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
# Step 7: Ask for Telegram bot token and chat ID
# -------------------------------------------
echo -e "${YELLOW}[7/10] Telegram bot configuration...${NC}"

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
# Step 8: Create notification script
# -------------------------------------------
echo -e "${YELLOW}[8/10] Creating Telegram notification script...${NC}"

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
# Step 9: Create action file
# -------------------------------------------
echo -e "${YELLOW}[9/10] Creating Fail2Ban action configuration...${NC}"

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

# -------------------------------------------
# Step 10: Restore banned IPs if this was a reinstall
# -------------------------------------------
if [ "$NEED_RESTORE" = true ] && [ -f banned_ips.txt ]; then
    echo -e "${YELLOW}[10/10] Restoring banned IPs from backup...${NC}"

    while read line; do
        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            jail="${BASH_REMATCH[1]}"
        elif [[ -n "$line" ]]; then
            for ip in $line; do
                echo -e "  Restoring ${CYAN}$ip${NC} → jail ${CYAN}$jail${NC}"
                sudo fail2ban-client set "$jail" banip "$ip" 2>/dev/null || true
            done
        fi
    done < banned_ips.txt

    # Clean up backup file
    rm -f banned_ips.txt
    echo -e "${GREEN}✓ Banned IPs restored and backup file removed${NC}"
    echo ""
fi

# -------------------------------------------
# Complete
# -------------------------------------------
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

if [ "$NEED_RESTORE" = true ]; then
    echo -e "  Reinstallation:  ${GREEN}✓${NC}"
fi
echo -e "  Server name:     ${CYAN}$SERVER_NAME${NC}"
echo -e "  Fail2Ban:        ${GREEN}✓${NC}"
echo -e "  Telegram script: ${GREEN}✓${NC}"
echo ""
echo -e "To check Fail2Ban status: ${CYAN}sudo fail2ban-client status${NC}"
echo ""
