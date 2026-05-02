#!/bin/bash
# ===========================================================================
# Name:         NaiveProxy Secure Installer
# Description:  The most advanced NaiveProxy installer — auto‑swap, fail2ban, 
#               BBR, rate limiting, corporate site simulation, QR configs,
#               custom SSH port, system maintenance, system info, 
#               firewall (UFW/firewalld), auto‑updates, and limits tuning.
#               Works on 7 Linux distros. One command.
# Author:       Kordan (krdn-dev)
# GitHub:       https://github.com/krdn-dev/naiveproxy-installer
# License:      MIT
# ===========================================================================

export LANG=en_US.UTF-8

# =====================================
# Colors and styles
# =====================================
RED="\033[91m"
GREEN="\033[92m"
YELLOW="\033[93m"
BLUE="\033[94m"
PLAIN="\033[0m"

red() { echo -e "${RED}${1}${PLAIN}"; }
green() { echo -e "${GREEN}${1}${PLAIN}"; }
yellow() { echo -e "${YELLOW}${1}${PLAIN}"; }
blue() { echo -e "${BLUE}${1}${PLAIN}"; }

# =====================================
# SSH port (will be asked during installation)
# =====================================
SSH_PORT=22

# =====================================
# Definition of the system
# =====================================
REGEX=("debian" "ubuntu" "centos|red hat|kernel" "oracle linux" "alma" "rocky" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "Oracle Linux" "AlmaLinux" "Rocky Linux" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "yum -y install" "yum -y install")

# =====================================
# Function: Show system information
# =====================================
show_system_info() {
    clear
    echo "#################################################"
    echo -e "--${GREEN}System Information${PLAIN}-------------------${BLUE}Kordan${PLAIN}--"
    echo "#################################################"
    echo ""
    
    # OS
    echo -e "${GREEN}Operating System:${PLAIN} $SYSTEM $VERSION"
    
    # Architecture
    echo -e "${GREEN}Architecture:${PLAIN} $(uname -m)"
    
    # Kernel
    echo -e "${GREEN}Kernel:${PLAIN} $(uname -r)"
    
    # Uptime
    echo -e "${GREEN}Uptime:${PLAIN} $(uptime -p | sed 's/up //')"
    
    # CPU
    echo -e "${GREEN}CPU:${PLAIN} $(nproc) cores"
    
    # RAM
    TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
    USED_RAM=$(free -h | awk '/^Mem:/ {print $3}')
    FREE_RAM=$(free -h | awk '/^Mem:/ {print $4}')
    RAM_PERCENT=$(free | awk '/^Mem:/ {printf "%.1f%%", $3/$2 * 100.0}')
    echo -e "${GREEN}RAM:${PLAIN} Total: $TOTAL_RAM, Used: $USED_RAM, Free: $FREE_RAM ($RAM_PERCENT)"
    
    # Swap
    if swapon --show 2>/dev/null | grep -q "/swapfile"; then
        SWAP_SIZE=$(swapon --show --bytes | awk '/swapfile/ {print $3}' | numfmt --to=iec 2>/dev/null || echo "unknown")
        echo -e "${GREEN}Swap:${PLAIN} $SWAP_SIZE (active)"
    else
        echo -e "${GREEN}Swap:${PLAIN} not configured"
    fi
    
    # Disk
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    DISK_PERCENT=$(df / | awk 'NR==2 {print $5}')
    echo -e "${GREEN}Disk (/):${PLAIN} Total: $DISK_TOTAL, Used: $DISK_USED, Free: $DISK_FREE ($DISK_PERCENT)"
    
    # Network
    SERVER_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "unknown")
    echo -e "${GREEN}External IP:${PLAIN} $SERVER_IP"
    
    # Active connections
    CONNS=$(ss -t state established | wc -l)
    echo -e "${GREEN}Active connections:${PLAIN} $CONNS"
    
    # Firewall
    case $SYSTEM in
        "Debian"|"Ubuntu")
            if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
                echo -e "${GREEN}Firewall:${PLAIN} UFW (active)"
            else
                echo -e "${GREEN}Firewall:${PLAIN} not active"
            fi
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            if systemctl is-active --quiet firewalld 2>/dev/null; then
                echo -e "${GREEN}Firewall:${PLAIN} firewalld (active)"
            else
                echo -e "${GREEN}Firewall:${PLAIN} not active"
            fi
            ;;
        *)
            echo -e "${GREEN}Firewall:${PLAIN} unknown"
            ;;
    esac
    
    # TCP congestion
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        echo -e "${GREEN}TCP congestion:${PLAIN} BBR"
    else
        echo -e "${GREEN}TCP congestion:${PLAIN} $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'unknown')"
    fi
    
    # Service Status
    echo ""
    echo -e "${YELLOW}Service Status:${PLAIN}"
    
    if systemctl is-active --quiet caddy 2>/dev/null; then
        echo -e "  ${GREEN}✓ Caddy: running${PLAIN}"
    else
        echo -e "  ${RED}✗ Caddy: not running${PLAIN}"
    fi
    
    if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban 2>/dev/null; then
        JAILED=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print $4}' || echo "0")
        echo -e "  ${GREEN}✓ fail2ban: running (banned: $JAILED IPs)${PLAIN}"
    else
        echo -e "  ${RED}✗ fail2ban: not running${PLAIN}"
    fi
    
    # NaiveProxy status
    if is_naive_installed; then
        echo -e "  ${GREEN}✓ NaiveProxy: installed${PLAIN}"
        echo -e "  ${GREEN}  Config:${PLAIN} /root/naive/naive-client.json"
    else
        echo -e "  ${RED}✗ NaiveProxy: not installed${PLAIN}"
    fi
    
    # Public ports (без localhost)
    echo ""
    echo -e "${YELLOW}Public ports (accessible from internet):${PLAIN}"
    PUBLIC_PORTS=$(ss -tlnp 2>/dev/null | grep -v "127.0.0.1" | grep -v "::1" | awk '{print $4}' | grep -oE ':[0-9]+$' | sort -u | sed 's/://')
    if [[ -n "$PUBLIC_PORTS" ]]; then
        echo "$PUBLIC_PORTS" | sed 's/^/  /'
    else
        echo "  none"
    fi
   
    echo ""
	echo "#################################################"
}

# =====================================
# Function: System maintenance (update, upgrade, clean)
# =====================================
system_maintenance() {
    clear
    echo "#################################################"
    echo -e "--${GREEN}System Maintenance${PLAIN}-------------------${BLUE}Kordan${PLAIN}--"
    echo "#################################################"
    echo ""
    
    case $SYSTEM in
        "Debian"|"Ubuntu")
            yellow "Updating package lists ..."
            apt-get update -qq
            green "✓ Package lists updated"
            
            echo ""
            yellow "Upgrading packages (full-upgrade) ..."
            apt-get full-upgrade -y
            green "✓ Packages upgraded"
            
            echo ""
            yellow "Cleaning up ..."
            apt-get autoremove -y
            apt-get autoclean -y
            green "✓ Cleanup completed"
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            yellow "Updating packages ..."
            dnf update -y
            green "✓ Packages updated"
            
            echo ""
            yellow "Cleaning up old kernels and packages ..."
            dnf autoremove -y
            dnf clean all
            package-cleanup --oldkernels --count=2 2>/dev/null || true
            green "✓ Cleanup completed"
            ;;
        *)
            yellow "Unknown OS — skipping maintenance"
            ;;
    esac
    
    green "✓ System maintenance completed!"
	echo ""
	echo "#################################################"
    echo ""
}

# =====================================
# Function: Check system requirements
# =====================================
check_system_requirements() {
    # ----- Root check -----
    if [[ $EUID -ne 0 ]]; then
        red "ATTENTION: Run the script as root user"
        exit 1
    fi
    
    # ----- Definition of an operating system -----
    CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")
    
    for i in "${CMD[@]}"; do
        SYS="$i" && [[ -n $SYS ]] && break
    done
    
    for ((int = 0; int < ${#REGEX[@]}; int++)); do
        [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && break
    done
    
    if [[ -z $SYSTEM ]]; then
        red "Your operating system is not supported!"
        exit 1
    fi
	
    if [[ -f /etc/almalinux-release ]]; then
        SYSTEM="AlmaLinux"
    elif [[ -f /etc/rocky-release ]]; then
        SYSTEM="Rocky Linux"
    fi
    
    # ----- Checking minimum OS versions -----
    case $SYSTEM in
        "Debian")
            VERSION=$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release 2>/dev/null)
            [[ -z $VERSION ]] && VERSION=$(grep -oP '(?<=VERSION=)[0-9]+' /etc/os-release 2>/dev/null)
            if [[ $VERSION -lt 11 ]]; then
                red "Debian $VERSION too old! Requires Debian 11 or later"
                exit 1
            fi
            ;;
        "Ubuntu")
            VERSION=$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release 2>/dev/null)
            if [[ $VERSION -lt 20 ]]; then
                red "Ubuntu $VERSION Too old! Requires Ubuntu 20.04 or later"
                exit 1
            fi
            ;;
        "CentOS"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            VERSION=$(grep -oE '[0-9]+' /etc/os-release 2>/dev/null | head -1)
            if [[ -z "$VERSION" ]] && [[ -f /etc/centos-release ]]; then
                VERSION=$(grep -oE '[0-9]+' /etc/centos-release | head -1)
            fi
            if [[ $VERSION -lt 8 ]]; then
                red "$SYSTEM $VERSION too old! Requires version 8 or later"
                exit 1
            fi
            ;;
        "Fedora")
            VERSION=$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release 2>/dev/null)
            if [[ $VERSION -lt 37 ]]; then
                red "Fedora $VERSION Too old! Requires Fedora 37 or later"
                exit 1
            fi
            ;;
    esac
    
    green "  $SYSTEM $VERSION"
}

# =====================================
# Function: Configure automatic updates based on OS
# =====================================
setup_auto_updates() {
    yellow "Setting up automatic security updates ..."
    
    case $SYSTEM in
        "Debian"|"Ubuntu")
            # Устанавливаем пакет
            if ! dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed"; then
                ${PACKAGE_INSTALL[int]} unattended-upgrades -y 2>/dev/null
            fi
            
            # Basic settings (20auto-upgrades)
            cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

            # Detailed settings (50unattended-upgrades)
            cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}:\${distro_codename}-updates";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

            systemctl restart unattended-upgrades 2>/dev/null
            green "Unattended upgrades are enabled"
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            # Installing dnf-automatic
            ${PACKAGE_INSTALL[int]} dnf-automatic -y 2>/dev/null
            # Setting up
            sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf 2>/dev/null
            systemctl enable --now dnf-automatic.timer 2>/dev/null
            green "Automatic updates (dnf-automatic) are enabled"
            ;;
        *)
            yellow "Automatic updates are not configured (ОС: $SYSTEM)"
            ;;
    esac
}

# =====================================
# Function: Setting up fail2ban (brute force protection)
# =====================================
setup_fail2ban() {
    yellow "Configuring fail2ban to protect SSH (port: $SSH_PORT) ..."
    
    # Installing fail2ban
    if ! command -v fail2ban-client &>/dev/null; then
        ${PACKAGE_INSTALL[int]} fail2ban -y 2>/dev/null
    fi
    
    # Checking if fail2ban is installed
    if ! command -v fail2ban-client &>/dev/null; then
        yellow "fail2ban is not installed (skip)"
        return 0
    fi
    
    # Create a folder if it doesn't exist
    mkdir -p /etc/fail2ban
    
    # Setting up
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = firewallcmd-ipset

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/secure
EOF

    # For Debian/Ubuntu the log is different
    if [[ $SYSTEM == "Debian" ]] || [[ $SYSTEM == "Ubuntu" ]]; then
        sed -i 's|/var/log/secure|/var/log/auth.log|' /etc/fail2ban/jail.local
        sed -i 's|banaction = firewallcmd-ipset|banaction = ufw|' /etc/fail2ban/jail.local
    fi

    systemctl enable fail2ban 2>/dev/null
    systemctl restart fail2ban 2>/dev/null
    
    if systemctl is-active --quiet fail2ban; then
        green "fail2ban is activated (SSH port: $SSH_PORT)"
    else
        yellow "fail2ban is not activated (not critical)"
    fi
}

# =====================================
# Function: Check architecture, RAM, disk
# =====================================
check_hardware_requirements() {
    # ----- Checking the processor architecture -----
    case "$(uname -m)" in
        x86_64|amd64) green "Architecture: x86_64" ;;
        aarch64|arm64) green "Architecture: ARM64" ;;
        *) red "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac
    
    # ----- Checking RAM -----
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_RAM -lt 256 ]]; then
        red "Not enough RAM: ${TOTAL_RAM}MB (minimum 256MB required))"
        exit 1
    elif [[ $TOTAL_RAM -lt 512 ]]; then
        yellow "RAM ${TOTAL_RAM}MB may not be enough to compile Caddy"
    else
        green "RAM: ${TOTAL_RAM}MB"
    fi
    
    # ----- Checking free space -----
    FREE_SPACE=$(df -m / | awk 'NR==2 {print $4}')
    if [[ $FREE_SPACE -lt 1024 ]]; then
        red "Not enough free space: ${FREE_SPACE}MB (minimum required 1GB)"
        exit 1
    else
        green "Free space: ${FREE_SPACE}MB"
    fi
}

# =====================================
# Function: Create swap file if low memory
# =====================================
setup_swap() {
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    
    # Checking if swap is needed
    if [[ $TOTAL_RAM -ge 4096 ]]; then
        green "RAM: ${TOTAL_RAM}MB, swap not required"
        return 0
    fi
    
    # Checking if there is already a swap
    if swapon --show | grep -q "/swapfile"; then
        green "Swap already configured"
        return 0
    fi
    
    # Determining the swap size
    if [[ $TOTAL_RAM -lt 512 ]]; then
        SWAP_SIZE=2          # Less 512MB → 2GB swap
    elif [[ $TOTAL_RAM -lt 1024 ]]; then
        SWAP_SIZE=1.5        # 512-1024MB → 1.5GB swap
    elif [[ $TOTAL_RAM -lt 2048 ]]; then
        SWAP_SIZE=1          # 1-2GB → 1GB swap
    elif [[ $TOTAL_RAM -lt 4096 ]]; then
        SWAP_SIZE=2          # 2-4GB → 2GB swap
    else
        SWAP_SIZE=2          # >4GB but we still create 2GB
    fi
    
    yellow "Low memory detected (${TOTAL_RAM}MB). Creating ${SWAP_SIZE}GB swap file ..."
    
    # Convert 1.5 to 1536MB for fallocate
    if [[ "$SWAP_SIZE" == "1.5" ]]; then
        SWAP_MB=1536
    else
        SWAP_MB=$((SWAP_SIZE * 1024))
    fi
    
    # Create a swap file
    swapoff /swapfile 2>/dev/null || true
    rm -f /swapfile 2>/dev/null || true
    
    # Let's try fallocate (quickly)
    if fallocate -l ${SWAP_MB}M /swapfile 2>/dev/null; then
        chmod 600 /swapfile
        mkswap /swapfile 2>/dev/null
        swapon /swapfile 2>/dev/null
        
        if ! grep -q "^/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        fi
        
        green "Swap file created (${SWAP_SIZE}GB / ${SWAP_MB}MB)"
    else
        # fallback на dd (slower)
        yellow "fallocate failed, using dd (may take a moment) ..."
        dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_MB 2>/dev/null
        chmod 600 /swapfile
        mkswap /swapfile 2>/dev/null
        swapon /swapfile 2>/dev/null
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
        green "Swap file created with dd (${SWAP_SIZE}GB)"
    fi
}

install_base_packages() {
    yellow "Installing base packages ..."
    
    # ----- Updating the package list (carefully for CentOS) -----
    if [[ $SYSTEM == "CentOS" ]] && [[ ${VERSION:-0} -ge 8 ]]; then
        ${PACKAGE_UPDATE[int]} 2>/dev/null || true
    elif [[ $SYSTEM != "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    
    # ----- For CentOS/RHEL/Alma/Rocky, enable EPEL -----
    if [[ $SYSTEM == "CentOS" ]] || [[ $SYSTEM == "Fedora" ]] || [[ $SYSTEM == "AlmaLinux" ]] || [[ $SYSTEM == "Rocky Linux" ]]; then
        if ! rpm -q epel-release &>/dev/null && ! rpm -q epel-next-release &>/dev/null; then
            yellow "Connecting the EPEL repository ..."
            ${PACKAGE_INSTALL[int]} epel-release -y 2>/dev/null
        fi
    fi
    
    # ----- For Oracle Linux -----
    if [[ $SYSTEM == "Oracle Linux" ]]; then
        if ! dnf repolist | grep -q "ol10_developer_EPEL"; then
            yellow "Connecting Oracle Linux EPEL repository ..."
            ${PACKAGE_INSTALL[int]} oracle-epel-release-el10 -y 2>/dev/null
        fi
    fi
    
    # ----- Installing common packages -----
    ${PACKAGE_INSTALL[int]} curl wget git
    
    # ----- Installing dnsutils for dig -----
    if ! command -v dig &>/dev/null; then
        yellow "Installation dnsutils (dig) ..."
        ${PACKAGE_INSTALL[int]} dnsutils 2>/dev/null || ${PACKAGE_INSTALL[int]} bind-utils 2>/dev/null
    fi
    
    # ----- Installing compilers -----
    if [[ $SYSTEM == "Debian" ]] || [[ $SYSTEM == "Ubuntu" ]]; then
        ${PACKAGE_INSTALL[int]} build-essential
    else
        ${PACKAGE_INSTALL[int]} gcc gcc-c++ make
    fi
    
    # ----- qrencode -----
    if ! command -v qrencode &>/dev/null; then
        ${PACKAGE_INSTALL[int]} qrencode 2>/dev/null || yellow "qrencode not installed (QR codes will not work)"
    else
        green "qrencode already installed"
    fi
    
    green "Basic packages are installed"
}

# =====================================
# Function: Configure firewall
# =====================================
configure_firewall() {
    yellow "Configuring firewall (SSH port: $SSH_PORT)..."
    
    case $SYSTEM in
        "Debian"|"Ubuntu")
            if ! command -v ufw &>/dev/null; then
                ${PACKAGE_INSTALL[int]} ufw -y 2>/dev/null
            fi
            sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw 2>/dev/null
            ufw --force reset 2>/dev/null
            ufw default deny incoming 2>/dev/null
            ufw default allow outgoing 2>/dev/null
            ufw allow "$SSH_PORT"/tcp 2>/dev/null
            ufw allow 80/tcp 2>/dev/null
            ufw allow 443/tcp 2>/dev/null
            ufw --force enable 2>/dev/null
            green "UFW firewall configured (SSH port: $SSH_PORT)"
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            if ! command -v firewall-cmd &>/dev/null; then
                ${PACKAGE_INSTALL[int]} firewalld -y 2>/dev/null
            fi
            systemctl enable --now firewalld 2>/dev/null
            firewall-cmd --permanent --add-port="$SSH_PORT"/tcp 2>/dev/null
            firewall-cmd --permanent --add-port=80/tcp 2>/dev/null
            firewall-cmd --permanent --add-port=443/tcp 2>/dev/null
            firewall-cmd --reload 2>/dev/null
            green "firewalld configured (SSH port: $SSH_PORT)"
            ;;
        *)
            yellow "Unknown OS — firewall not configured automatically"
            ;;
    esac
}

# =====================================
# Function: Change SSH port
# =====================================
change_ssh_port() {
    # Определяем текущий активный порт SSH
    CURRENT_SSH_PORT=$(ss -tlnp | grep -oP '(?<=:)\d+(?=.*sshd)' | head -n1)
    [[ -z "$CURRENT_SSH_PORT" ]] && CURRENT_SSH_PORT=22
    
    if [[ $SSH_PORT -eq $CURRENT_SSH_PORT ]]; then
        green "○ SSH port already set to $SSH_PORT (no changes needed)"
        return 0
    fi
    
    yellow "Changing SSH port from $CURRENT_SSH_PORT to $SSH_PORT..."
    
    # Изменяем порт в конфиге
    sed -i "s/^#Port $CURRENT_SSH_PORT/Port $SSH_PORT/" /etc/ssh/sshd_config
    sed -i "s/^Port $CURRENT_SSH_PORT/Port $SSH_PORT/" /etc/ssh/sshd_config
    
    # Добавляем, если строки нет
    if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
        echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
    fi
    
    # Проверяем конфиг перед перезапуском
    if sshd -t; then
        systemctl restart sshd
        green "✓ SSH port changed from $CURRENT_SSH_PORT to $SSH_PORT"
        echo ""
        yellow "○ Current session remains active on port $CURRENT_SSH_PORT"
        yellow "○ Next time connect using: ssh -p $SSH_PORT root@$SERVER_IP"
    else
        red "✗ SSH config test failed! Port not changed."
        return 1
    fi
}

# =====================================
# Function: Go Installation
# =====================================
install_go() {
    yellow "Checking the latest version of Go ..."

    LATEST_GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1)

    if [[ -z "$LATEST_GO_VERSION" ]]; then
        red "Unable to get the latest version of Go. Check your connection"
        exit 1
    fi

    GO_VERSION="${LATEST_GO_VERSION#go}"
	green "Latest stable version: $GO_VERSION"

    # ----- Defining the architecture -----
    if [[ "$(uname -m)" == "x86_64" ]]; then
        ARCH="amd64"
    elif [[ "$(uname -m)" == "aarch64" ]]; then
        ARCH="arm64"
    else
        red "Unsupported processor architecture: $(uname -m)"
        exit 1
    fi

    GO_ARCHIVE="${LATEST_GO_VERSION}.linux-${ARCH}.tar.gz"
    DOWNLOAD_URL="https://go.dev/dl/${GO_ARCHIVE}"

    rm -rf /usr/local/go

    yellow "Downloading $LATEST_GO_VERSION for linux/$ARCH ..."
    wget -q --show-progress "$DOWNLOAD_URL" -O /tmp/go.tar.gz

    if [[ $? -ne 0 ]]; then
        red "Error downloading Go. Please check your connection"
        exit 1
    fi

    yellow "Installing Go in /usr/local ..."
    tar -C /usr/local -xzf /tmp/go.tar.gz

    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    export PATH=$PATH:/usr/local/go/bin

    rm -f /tmp/go.tar.gz

    if ! command -v go &>/dev/null; then
        red "Error: Go was not installed"
        exit 1
    fi

    green "Go ${GO_VERSION} successfully installed!"
}

# =====================================
# Function: Build Caddy with the forwardproxy plugin
# =====================================
build_caddy() {
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

    mkdir -p /root/tmp
    export TMPDIR=/root/tmp

    yellow "Building Caddy with the forwardproxy plugin (may take 3-5 minutes) ..."
    ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive --with github.com/mholt/caddy-ratelimit

    mv caddy /usr/bin/caddy
    chmod +x /usr/bin/caddy
}

# =====================================
# Function: User input parameters
# =====================================
input_parameters() {
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                      CONFIGURATION WIZARD"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # ----- Entering SSH port -----
    while true; do
        echo ""
        blue "→ SSH configuration:"
        echo "  [1] 22    (Default — standard SSH port)"
        echo "  [2] Custom port (range 1024-65535)"
        echo ""
        read -rp "$(green "Your choice [1-2]: ")" ssh_choice

        case $ssh_choice in
            1)
                SSH_PORT=22
                green "✓ SSH port set to: 22"
                break
                ;;
            2)
                read -rp "$(yellow "Enter custom SSH port (1024-65535): ")" ssh_port_input
                if [[ "$ssh_port_input" =~ ^[0-9]+$ ]] && [ "$ssh_port_input" -ge 1024 ] && [ "$ssh_port_input" -le 65535 ]; then
                    SSH_PORT="$ssh_port_input"
                    green "✓ SSH port set to: $SSH_PORT"
                    break
                else
                    red "✗ Error: Invalid port — must be number between 1024 and 65535"
                fi
                ;;
            *)
                red "✗ Invalid choice — please select 1 or 2"
                ;;
        esac
    done

    # ----- Entering NaiveProxy port -----
    while true; do    
        echo ""
        blue "→ NaiveProxy port selection:"
        echo "  [1] 443  (Recommended — best camouflage)"
        echo "  [2] 8443 (Alternative — often allowed in corporate networks)"
        echo "  [3] Custom port (range 1024-65535)"
        echo ""
        read -rp "$(green "Your choice [1-3]: ")" port_choice

        case $port_choice in
            1)
                proxyport=443
                ;;
            2)
                proxyport=8443
                ;;
            3)
                read -rp "$(yellow "Enter custom port (1024-65535): ")" proxyport
                if [[ ! "$proxyport" =~ ^[0-9]+$ ]] || [ "$proxyport" -lt 1024 ] || [ "$proxyport" -gt 65535 ]; then
                    red "✗ Error: Invalid port — must be number between 1024 and 65535"
                    continue
                fi
                ;;
            *)
                red "✗ Invalid choice — please select 1, 2, or 3"
                continue
                ;;
        esac
        
        # ----- Checking port occupancy -----
        if ss -tlnp | grep -q ":$proxyport "; then
            red "✗ Port $proxyport is already in use by another process!"
            echo ""
            yellow "Please select another port:"
            continue
        fi
        
        green "✓ Port $proxyport selected and available"
        break
    done

    # ----- Entering domain -----
    while true; do
        echo ""
        read -rp "$(blue "→ Enter your domain (e.g., example.com): ")" domain
        
        if [[ -z $domain ]]; then
            red "✗ The domain cannot be empty!"
            continue
        fi
        
        if ! echo "$domain" | grep -qP '^(?=[a-z0-9-]{1,63}\.)([a-z0-9-]+\.)+[a-z]{2,}$'; then
            red "✗ Incorrect domain format — use example.com"
            continue
        fi
        
        yellow "→ Checking DNS..."
        SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || curl -s --max-time 5 ipinfo.io/ip 2>/dev/null)
        DOMAIN_IP=$(dig +short "$domain" | head -1)
        
        if [[ -z "$DOMAIN_IP" ]]; then
            red "✗ Domain $domain does not resolve to an IP address"
            yellow "→ Fix your DNS records and try again"
            continue
        fi
        
        if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
            red "✗ Domain $domain points to $DOMAIN_IP, but server IP is $SERVER_IP"
            red "→ Fix your A record and try again"
            continue
        fi
        
        green "✓ DNS check passed: $domain → $DOMAIN_IP"
        break
    done

    # ----- Entering email -----
    while true; do
        echo ""
        read -rp "$(blue "→ Enter email for Let's Encrypt certificate: ")" email
        
        if [[ -z $email ]]; then
            red "✗ Email cannot be empty!"
            continue
        fi
        
        if ! echo "$email" | grep -qP '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
            red "✗ Incorrect email format — use user@example.com"
            continue
        fi
        
        green "✓ Email is valid: $email"
        break
    done

    # ----- Entering username -----
    while true; do
        echo ""
        read -rp "$(yellow "→ Enter username [press Enter for random]: ")" proxyname
        
        if [[ -z $proxyname ]]; then
            if command -v openssl &>/dev/null; then
                proxyname=$(openssl rand -hex 8)
            else
                proxyname=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16)
            fi
            green "✓ Username generated: $proxyname"
            break
        else
            if [[ ${#proxyname} -lt 3 ]]; then
                red "✗ Username must be at least 3 characters"
                continue
            fi
            green "✓ Username set: $proxyname"
            break
        fi
    done

    # ----- Entering password -----
    while true; do
        echo ""
        read -rp "$(yellow "→ Enter password [press Enter for random]: ")" proxypwd
        
        if [[ -z $proxypwd ]]; then
            if command -v openssl &>/dev/null; then
                proxypwd=$(openssl rand -hex 12)
            else
                proxypwd=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 24)
            fi
            green "✓ Password generated: $proxypwd"
            break
        else
            if [[ ${#proxypwd} -lt 6 ]]; then
                red "✗ Password must be at least 6 characters"
                continue
            fi
            green "✓ Password set"
            break
        fi
    done
    
    echo ""
    green "✓ Configuration completed successfully!"
    echo ""
}	

# =====================================
# Function: Creating configuration files
# =====================================
create_configs() {
    # ----- Caddyfile -----
    cat << EOF > /etc/caddy/Caddyfile
{
    order forward_proxy before file_server
    admin localhost:2019
}

:${proxyport}, ${domain}:${proxyport} {
    tls ${email}

    forward_proxy {
        basic_auth ${proxyname} ${proxypwd}
        hide_ip
        hide_via
        probe_resistance
    }

    file_server {
        root /var/www/html
    }
    
    # Rate limiting — DDoS and brute force protection
    rate_limit {
        zone dynamic {
            key {remote_host}
            events 100
            window 1m
        }
        zone static {
            key {remote_host}
            events 10
            window 1s
        }
    }
}

:80 {
    redir https://${domain}:${proxyport}{uri} permanent
}
EOF

    # ----- Client configuration -----
    mkdir -p /root/naive
    cat <<EOF > /root/naive/naive-client.json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://${proxyname}:${proxypwd}@${domain}:${proxyport}",
  "log": ""
}
EOF

    # ----- Link for clients -----
    url="naive+https://${proxyname}:${proxypwd}@${domain}:${proxyport}?padding=true#Naive-${domain}"
    echo "$url" > /root/naive/naive-url.txt
}

# =====================================
# Function: Create a systemd service
# =====================================
create_systemd_service() {
    cat << EOF > /etc/systemd/system/caddy.service
[Unit]
Description=Caddy web server (NaiveProxy)
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable caddy
    systemctl start caddy
}

# =====================================
# Function: Enable BBR
# =====================================
enable_bbr() {
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        green "BBR is On"
    fi
}

# =====================================
# Function: Disable unnecessary services
# =====================================
disable_unnecessary_services() {
    yellow "Disabling unnecessary services for security..."
    
    # Базовый список для всех систем
    local services=("avahi-daemon" "bluetooth" "cups" "cups-browsed" "ModemManager" "packagekit")
    
    # Ubuntu/Debian специфичные
    if [[ $SYSTEM == "Ubuntu" ]] || [[ $SYSTEM == "Debian" ]]; then
        services+=("whoopsie" "snapd")
    fi
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service.service"; then
            systemctl disable --now "$service" 2>/dev/null && green "  $service disabled"
        fi
    done
}

# =====================================
# Function: Optimize sysctl for proxy
# =====================================
optimize_sysctl() {
    yellow "Applying sysctl optimizations for proxy..."
    
    cat > /etc/sysctl.d/99-naiveproxy.conf << EOF
# === NaiveProxy optimizations ===
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.ip_local_port_range = 1024 65535

# === Basic anti-spoofing protection ===
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# === Protection against SYN-flood and DDoS ===
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 16384
net.core.netdev_max_backlog = 8192

# === Protection against MITM, reconnaissance, and fingerprinting ===
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# === Disabling IPv6 completely (hard) ===
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# === ASLR – Exploit Resistance ===
kernel.randomize_va_space = 2

# === Network optimizations for high load ===
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 180
net.ipv4.tcp_keepalive_intvl = 20
net.ipv4.tcp_keepalive_probes = 5

# === Reducing swapping ===
vm.swappiness = 10

# === Increasing limits ===
fs.file-max = 2097152
EOF

    sysctl -p /etc/sysctl.d/99-naiveproxy.conf 2>/dev/null
    green "Sysctl optimizations applied"
}

# =====================================
# Function: Increase system limits
# =====================================
increase_limits() {
    yellow "Increasing system limits for high-load performance..."
    
    LIMIT_VALUE=2097152
    
    cat > /etc/security/limits.conf << EOF
* soft nofile ${LIMIT_VALUE}
* hard nofile ${LIMIT_VALUE}
root soft nofile ${LIMIT_VALUE}
root hard nofile ${LIMIT_VALUE}
EOF

    green "System limits increased to ${LIMIT_VALUE} open files"
}

# =====================================
# Function: Create a complete website structure
# =====================================
create_landing_page() {
    yellow "Creating complete website structure for $domain ..."
    
    mkdir -p /var/www/html
    mkdir -p /var/www/html/about
    mkdir -p /var/www/html/contact
    mkdir -p /var/www/html/blog
    mkdir -p /var/www/html/news
    
    # =====================================
    # robots.txt
    # =====================================
    cat > /var/www/html/robots.txt << EOF
User-agent: *
Allow: /
Sitemap: https://${domain}/sitemap.xml
EOF

    # =====================================
    # sitemap.xml
    # =====================================
    cat > /var/www/html/sitemap.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://${domain}/</loc><lastmod>2026-05-01</lastmod><changefreq>daily</changefreq><priority>1.0</priority></url>
  <url><loc>https://${domain}/about/</loc><lastmod>2026-04-15</lastmod><changefreq>monthly</changefreq><priority>0.8</priority></url>
  <url><loc>https://${domain}/contact/</loc><lastmod>2026-04-15</lastmod><changefreq>monthly</changefreq><priority>0.8</priority></url>
  <url><loc>https://${domain}/blog/security-update-2026.html</loc><lastmod>2026-04-28</lastmod><changefreq>weekly</changefreq><priority>0.6</priority></url>
  <url><loc>https://${domain}/blog/network-expansion.html</loc><lastmod>2026-04-20</lastmod><changefreq>weekly</changefreq><priority>0.6</priority></url>
  <url><loc>https://${domain}/news/edge-location</loc><lastmod>2026-04-10</lastmod><changefreq>weekly</changefreq><priority>0.6</priority></url>
</urlset>
EOF

    # =====================================
    # Main index.html
    # =====================================
    cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>'${domain^^}' | Enterprise Portal</title>
    <meta name="description" content="Enterprise infrastructure and cloud solutions">
    <meta name="robots" content="index, follow">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', 'Inter', system-ui, sans-serif;
            background: radial-gradient(ellipse at 20% 30%, #0a0f1a, #03060c);
            min-height: 100vh;
            color: #e2e8f0;
            line-height: 1.6;
        }
        .particles { position: fixed; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: 0; }
        .particle {
            position: absolute;
            background: rgba(56, 189, 248, 0.15);
            border-radius: 50%;
            pointer-events: none;
            animation: float 20s infinite ease-in-out;
        }
        @keyframes float {
            0%, 100% { transform: translateY(0px) translateX(0px); opacity: 0.1; }
            50% { transform: translateY(-40px) translateX(30px); opacity: 0.4; }
        }
        .navbar {
            position: fixed;
            top: 0;
            width: 100%;
            background: rgba(15, 23, 42, 0.9);
            backdrop-filter: blur(12px);
            border-bottom: 1px solid rgba(56, 189, 248, 0.2);
            z-index: 100;
            padding: 1rem 2rem;
        }
        .nav-container {
            max-width: 1200px;
            margin: 0 auto;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 1rem;
        }
        .nav-logo {
            font-size: 1.5rem;
            font-weight: 700;
            background: linear-gradient(135deg, #38bdf8, #a855f7);
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
        }
        .nav-links { display: flex; gap: 2rem; flex-wrap: wrap; }
        .nav-links a { color: #cbd5e1; text-decoration: none; transition: color 0.2s; font-size: 0.9rem; }
        .nav-links a:hover { color: #38bdf8; }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 6rem 2rem 3rem;
            position: relative;
            z-index: 1;
        }
        .hero { text-align: center; margin-bottom: 4rem; }
        .logo {
            font-size: 4rem;
            font-weight: 800;
            margin-bottom: 0.5rem;
            background: linear-gradient(135deg, #38bdf8 0%, #a855f7 50%, #ec4899 100%);
            background-size: 200% 200%;
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
            animation: gradientShift 6s ease infinite;
        }
        @keyframes gradientShift {
            0% { background-position: 0% 50%; }
            50% { background-position: 100% 50%; }
            100% { background-position: 0% 50%; }
        }
        .subtitle { font-size: 1rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 4px; margin-bottom: 1.5rem; }
        .hero-badge { display: inline-flex; gap: 0.75rem; flex-wrap: wrap; justify-content: center; margin-bottom: 2rem; }
        .hero-badge span {
            background: rgba(255, 255, 255, 0.05);
            padding: 0.25rem 1rem;
            border-radius: 20px;
            font-size: 0.7rem;
            border: 1px solid rgba(56, 189, 248, 0.3);
        }
        .section-title {
            font-size: 1.8rem;
            margin-bottom: 1.5rem;
            text-align: center;
            background: linear-gradient(135deg, #f8fafc, #cbd5e1);
            -webkit-background-clip: text;
            background-clip: text;
            color: transparent;
        }
        .card {
            background: rgba(15, 23, 42, 0.5);
            backdrop-filter: blur(8px);
            border-radius: 24px;
            padding: 2rem;
            border: 1px solid rgba(56, 189, 248, 0.2);
            transition: transform 0.2s, border-color 0.2s;
            margin-bottom: 2rem;
        }
        .card:hover { border-color: rgba(56, 189, 248, 0.5); transform: translateY(-2px); }
        .status-badge {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            background: rgba(16, 185, 129, 0.12);
            color: #10b981;
            padding: 0.35rem 1rem;
            border-radius: 30px;
            font-size: 0.75rem;
            margin-bottom: 1.5rem;
            border: 1px solid rgba(16, 185, 129, 0.3);
        }
        .status-dot {
            width: 8px;
            height: 8px;
            background: #10b981;
            border-radius: 50%;
            animation: pulse 1.5s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.5; transform: scale(1.2); }
        }
        h2 { font-size: 1.6rem; margin-bottom: 1rem; font-weight: 600; }
        .features-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 1.5rem;
            margin: 2rem 0;
        }
        .feature-item {
            background: rgba(0, 0, 0, 0.3);
            border-radius: 16px;
            padding: 1.2rem;
            text-align: center;
            transition: all 0.2s;
            border: 1px solid rgba(255, 255, 255, 0.05);
        }
        .feature-item:hover {
            background: rgba(56, 189, 248, 0.08);
            border-color: rgba(56, 189, 248, 0.3);
        }
        .feature-icon { font-size: 2rem; margin-bottom: 0.5rem; display: block; }
        .feature-title { font-weight: 600; margin-bottom: 0.25rem; }
        .feature-desc { font-size: 0.75rem; color: #94a3b8; }
        .blog-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 1.5rem;
            margin: 1.5rem 0;
        }
        .blog-card {
            background: rgba(0, 0, 0, 0.25);
            border-radius: 16px;
            padding: 1.2rem;
            border-bottom: 2px solid #38bdf8;
        }
        .blog-date { font-size: 0.7rem; color: #38bdf8; margin-bottom: 0.5rem; }
        .blog-title { font-weight: 600; margin-bottom: 0.5rem; }
        .blog-excerpt { font-size: 0.8rem; color: #94a3b8; }
        .read-more {
            display: inline-block;
            margin-top: 0.5rem;
            font-size: 0.75rem;
            color: #38bdf8;
            text-decoration: none;
        }
        .contact-sim {
            background: rgba(0, 0, 0, 0.3);
            border-radius: 20px;
            padding: 1.5rem;
            margin: 2rem 0;
            text-align: center;
        }
        .contact-sim input {
            background: #1e293b;
            border: 1px solid #334155;
            border-radius: 30px;
            padding: 0.6rem 1.2rem;
            color: white;
            width: 260px;
            margin: 0.5rem;
        }
        .contact-sim button {
            background: linear-gradient(135deg, #1e293b, #0f172a);
            border: 1px solid #38bdf8;
            border-radius: 30px;
            padding: 0.6rem 1.5rem;
            color: #38bdf8;
            cursor: pointer;
            transition: all 0.2s;
        }
        .contact-sim button:hover {
            background: #38bdf8;
            color: #0f172a;
        }
        .footer {
            margin-top: 3rem;
            padding-top: 2rem;
            border-top: 1px solid rgba(255, 255, 255, 0.1);
            text-align: center;
            font-size: 0.7rem;
            color: #475569;
        }
        .footer-links {
            display: flex;
            justify-content: center;
            gap: 2rem;
            flex-wrap: wrap;
            margin-bottom: 1rem;
        }
        .footer-links a { color: #475569; text-decoration: none; }
        .footer-links a:hover { color: #38bdf8; }
        @media (max-width: 768px) {
            .nav-container { flex-direction: column; }
            .container { padding-top: 8rem; }
            .features-grid { grid-template-columns: 1fr; }
            .blog-grid { grid-template-columns: 1fr; }
            .logo { font-size: 2.5rem; }
        }
    </style>
</head>
<body>
<div class="particles" id="particles"></div>

<nav class="navbar">
    <div class="nav-container">
        <div class="nav-logo">${domain^^}</div>
        <div class="nav-links">
            <a href="/">Home</a>
            <a href="/about/">About</a>
            <a href="/contact/">Contact</a>
            <a href="/blog/">Blog</a>
        </div>
    </div>
</nav>

<div class="container">
    <div class="hero">
        <div class="hero-badge">
            <span>🔒 TLS 1.3</span>
            <span>⚡ HTTP/3 Ready</span>
            <span>🛡️ DNSSEC</span>
            <span>🌍 Anycast</span>
        </div>
        <div class="logo">${domain^^}</div>
        <div class="subtitle">Enterprise Infrastructure</div>
    </div>

    <div class="card">
        <div class="status-badge">
            <span class="status-dot"></span>
            <span>System Online | HA Cluster Active</span>
        </div>
        <h2>Corporate Portal</h2>
        <p>Welcome to the ${domain} corporate portal. High-availability infrastructure with geographic redundancy, DDoS protection, and real-time monitoring across all edge locations.</p>
    </div>

    <div class="features-grid">
        <div class="feature-item"><span class="feature-icon">🚀</span><div class="feature-title">Edge Network</div><div class="feature-desc">Global anycast routing</div></div>
        <div class="feature-item"><span class="feature-icon">🛡️</span><div class="feature-title">Advanced Security</div><div class="feature-desc">WAF + DDoS mitigation</div></div>
        <div class="feature-item"><span class="feature-icon">🌍</span><div class="feature-title">Geo-redundancy</div><div class="feature-desc">Multi-region failover</div></div>
        <div class="feature-item"><span class="feature-icon">⚡</span><div class="feature-title">99.99% Uptime</div><div class="feature-desc">SLA guaranteed</div></div>
    </div>

    <div class="blog-grid">
        <div class="blog-card"><div class="blog-date"><span id="blogDate1"></span></div><div class="blog-title">Infrastructure Upgrade Complete</div><div class="blog-excerpt">All systems are now running on the latest hardware revision.</div><a href="/blog/security-update-2026.html" class="read-more">Read more →</a></div>
        <div class="blog-card"><div class="blog-date"><span id="blogDate2"></span></div><div class="blog-title">New DDoS Protection Layer</div><div class="blog-excerpt">Enhanced mitigation capabilities now active across all edge nodes.</div><a href="/blog/network-expansion.html" class="read-more">Read more →</a></div>
        <div class="blog-card"><div class="blog-date"><span id="blogDate3"></span></div><div class="blog-title">Edge Location Launched</div><div class="blog-excerpt">New points of presence added in Asia-Pacific region.</div><a href="/news/edge-location" class="read-more">Read more →</a></div>
    </div>

    <div class="contact-sim">
        <p style="margin-bottom: 0.75rem;">Subscribe to infrastructure updates</p>
        <input type="email" placeholder="Your corporate email">
        <button onclick="alert('Demo mode: subscription would be sent to ' + document.domain)">Subscribe</button>
        <p style="font-size: 0.7rem; margin-top: 0.75rem; color:#475569;">Get notified about maintenance and new features</p>
    </div>

    <div class="footer">
        <div class="footer-links">
            <a href="/about/">About Us</a>
            <a href="/contact/">Contact</a>
            <a href="/blog/">Blog</a>
            <a href="https://www.cloudflare.com" target="_blank">Cloudflare</a>
            <a href="https://www.digitalocean.com" target="_blank">DigitalOcean</a>
        </div>
        <div>© <span id="currentYear"></span> ${domain} · Enterprise Infrastructure · All rights reserved</div>
        <div style="margin-top: 0.5rem;">Last updated: <span id="lastUpdated"></span></div>
    </div>
</div>

<script>
    // Particles
    const particlesContainer = document.getElementById('particles');
    for (let i = 0; i < 60; i++) {
        const p = document.createElement('div');
        p.classList.add('particle');
        const s = Math.random() * 6 + 2;
        p.style.width = s + 'px';
        p.style.height = s + 'px';
        p.style.left = Math.random() * 100 + '%';
        p.style.top = Math.random() * 100 + '%';
        p.style.animationDelay = Math.random() * 15 + 's';
        p.style.animationDuration = Math.random() * 20 + 10 + 's';
        particlesContainer.appendChild(p);
    }

    // Dynamic dates
    document.getElementById('currentYear').textContent = new Date().getFullYear();
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 
                    'July', 'August', 'September', 'October', 'November', 'December'];
    const now = new Date();
    const currentDate = months[now.getMonth()] + ' ' + now.getFullYear();
    document.getElementById('lastUpdated').textContent = currentDate;
    
    const lastMonth = months[(now.getMonth() - 1 + 12) % 12] + ' ' + now.getFullYear();
    const twoMonthsAgo = months[(now.getMonth() - 2 + 12) % 12] + ' ' + (now.getMonth() < 2 ? now.getFullYear() - 1 : now.getFullYear());
    document.getElementById('blogDate1').textContent = currentDate;
    document.getElementById('blogDate2').textContent = lastMonth;
    document.getElementById('blogDate3').textContent = twoMonthsAgo;
</script>
</body>
</html>
EOF

    # =====================================
    # About page
    # =====================================
    cat > /var/www/html/about/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>About | ${domain^^}</title>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: 'Segoe UI', system-ui, sans-serif;
        background: radial-gradient(ellipse at 20% 30%, #0a0f1a, #03060c);
        min-height: 100vh;
        color: #e2e8f0;
    }
    .navbar {
        position: fixed;
        top: 0;
        width: 100%;
        background: rgba(15, 23, 42, 0.9);
        backdrop-filter: blur(12px);
        border-bottom: 1px solid rgba(56, 189, 248, 0.2);
        padding: 1rem 2rem;
        z-index: 100;
    }
    .nav-container {
        max-width: 1200px;
        margin: 0 auto;
        display: flex;
        justify-content: space-between;
        align-items: center;
        flex-wrap: wrap;
        gap: 1rem;
    }
    .nav-logo {
        font-size: 1.5rem;
        font-weight: 700;
        background: linear-gradient(135deg, #38bdf8, #a855f7);
        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
    }
    .nav-links { display: flex; gap: 2rem; flex-wrap: wrap; }
    .nav-links a { color: #cbd5e1; text-decoration: none; font-size: 0.9rem; }
    .nav-links a:hover { color: #38bdf8; }
    .container { max-width: 1200px; margin: 0 auto; padding: 6rem 2rem 3rem; }
    h1 { font-size: 2.5rem; margin-bottom: 1rem; background: linear-gradient(135deg, #38bdf8, #a855f7); -webkit-background-clip: text; background-clip: text; color: transparent; }
    .card { background: rgba(15, 23, 42, 0.5); backdrop-filter: blur(8px); border-radius: 24px; padding: 2rem; border: 1px solid rgba(56, 189, 248, 0.2); margin-bottom: 2rem; }
    .footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid rgba(255,255,255,0.1); text-align: center; font-size: 0.7rem; color: #475569; }
</style>
</head>
<body>
<nav class="navbar">
    <div class="nav-container">
        <div class="nav-logo">${domain^^}</div>
        <div class="nav-links"><a href="/">Home</a><a href="/about/">About</a><a href="/contact/">Contact</a><a href="/blog/">Blog</a></div>
    </div>
</nav>
<div class="container">
    <h1>About ${domain}</h1>
    <div class="card">
        <p><strong>${domain} Infrastructure</strong> is a global edge network provider delivering high-performance, secure, and reliable connectivity solutions for enterprises worldwide.</p>
        <p style="margin-top: 1rem;">Founded in 2018, we have grown to operate points of presence across North America, Europe, and Asia-Pacific, serving thousands of business customers with industry-leading SLAs.</p>
    </div>
    <div class="card">
        <h2>Key Milestones</h2>
        <ul style="margin-left: 1.5rem; color: #94a3b8;">
            <li>2026: Expanded to 50+ global edge locations</li>
            <li>2025: Launched DDoS protection platform</li>
            <li>2024: Achieved SOC2 Type II certification</li>
            <li>2023: First data center in Asia-Pacific</li>
        </ul>
    </div>
    <div class="footer"><div>© <span id="year"></span> ${domain} · Enterprise Infrastructure</div></div>
</div>
<script>document.getElementById('year').textContent = new Date().getFullYear();</script>
</body>
</html>
EOF

    # =====================================
    # Contact page
    # =====================================
    cat > /var/www/html/contact/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Contact | ${domain^^}</title>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: 'Segoe UI', system-ui, sans-serif;
        background: radial-gradient(ellipse at 20% 30%, #0a0f1a, #03060c);
        min-height: 100vh;
        color: #e2e8f0;
    }
    .navbar {
        position: fixed;
        top: 0;
        width: 100%;
        background: rgba(15, 23, 42, 0.9);
        backdrop-filter: blur(12px);
        border-bottom: 1px solid rgba(56, 189, 248, 0.2);
        padding: 1rem 2rem;
        z-index: 100;
    }
    .nav-container {
        max-width: 1200px;
        margin: 0 auto;
        display: flex;
        justify-content: space-between;
        align-items: center;
        flex-wrap: wrap;
        gap: 1rem;
    }
    .nav-logo {
        font-size: 1.5rem;
        font-weight: 700;
        background: linear-gradient(135deg, #38bdf8, #a855f7);
        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
    }
    .nav-links { display: flex; gap: 2rem; flex-wrap: wrap; }
    .nav-links a { color: #cbd5e1; text-decoration: none; font-size: 0.9rem; }
    .nav-links a:hover { color: #38bdf8; }
    .container { max-width: 1200px; margin: 0 auto; padding: 6rem 2rem 3rem; }
    h1 { font-size: 2.5rem; margin-bottom: 1rem; background: linear-gradient(135deg, #38bdf8, #a855f7); -webkit-background-clip: text; background-clip: text; color: transparent; }
    .card { background: rgba(15, 23, 42, 0.5); backdrop-filter: blur(8px); border-radius: 24px; padding: 2rem; border: 1px solid rgba(56, 189, 248, 0.2); margin-bottom: 2rem; }
    .contact-info { color: #94a3b8; line-height: 2; }
    .footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid rgba(255,255,255,0.1); text-align: center; font-size: 0.7rem; color: #475569; }
</style>
</head>
<body>
<nav class="navbar">
    <div class="nav-container">
        <div class="nav-logo">${domain^^}</div>
        <div class="nav-links"><a href="/">Home</a><a href="/about/">About</a><a href="/contact/">Contact</a><a href="/blog/">Blog</a></div>
    </div>
</nav>
<div class="container">
    <h1>Contact ${domain}</h1>
    <div class="card">
        <div class="contact-info">
            <p><strong>📧 Email:</strong> <a href="mailto:admin@${domain}" style="color: #38bdf8;">admin@${domain}</a></p>
            <p><strong>📍 Global HQ:</strong> 123 Cloud Avenue, San Francisco, CA 94105</p>
            <p><strong>🌍 Regional Offices:</strong> London, Singapore, Frankfurt, Tokyo</p>
            <p><strong>🕒 Support:</strong> 24/7 Enterprise Support available</p>
        </div>
    </div>
    <div class="card">
        <h2>Get in Touch</h2>
        <p>For sales inquiries, technical support, or partnership opportunities, please reach out to our global team.</p>
        <p style="margin-top: 1rem;">📞 <strong>Sales:</strong> +1 (888) 123-4567<br>🛠️ <strong>Technical Support:</strong> support@${domain}</p>
    </div>
    <div class="footer"><div>© <span id="year"></span> ${domain} · Enterprise Infrastructure</div></div>
</div>
<script>document.getElementById('year').textContent = new Date().getFullYear();</script>
</body>
</html>
EOF

    # =====================================
    # Blog post 1
    # =====================================
    cat > /var/www/html/blog/security-update-2026.html << EOF
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Security Update | ${domain^^}</title>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: 'Segoe UI', system-ui, sans-serif;
        background: radial-gradient(ellipse at 20% 30%, #0a0f1a, #03060c);
        color: #e2e8f0;
    }
    .navbar {
        position: fixed;
        top: 0;
        width: 100%;
        background: rgba(15, 23, 42, 0.9);
        backdrop-filter: blur(12px);
        border-bottom: 1px solid rgba(56, 189, 248, 0.2);
        padding: 1rem 2rem;
        z-index: 100;
    }
    .nav-container {
        max-width: 1200px;
        margin: 0 auto;
        display: flex;
        justify-content: space-between;
        align-items: center;
        flex-wrap: wrap;
        gap: 1rem;
    }
    .nav-logo {
        font-size: 1.5rem;
        font-weight: 700;
        background: linear-gradient(135deg, #38bdf8, #a855f7);
        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
    }
    .nav-links { display: flex; gap: 2rem; flex-wrap: wrap; }
    .nav-links a { color: #cbd5e1; text-decoration: none; font-size: 0.9rem; }
    .nav-links a:hover { color: #38bdf8; }
    .container { max-width: 900px; margin: 0 auto; padding: 8rem 2rem 3rem; }
    .post-meta { color: #38bdf8; font-size: 0.8rem; margin-bottom: 1rem; }
    h1 { font-size: 2rem; margin-bottom: 1rem; }
    .content { line-height: 1.8; color: #94a3b8; }
    .content p { margin-bottom: 1rem; }
    .footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid rgba(255,255,255,0.1); text-align: center; font-size: 0.7rem; color: #475569; }
</style>
</head>
<body>
<nav class="navbar">
    <div class="nav-container">
        <div class="nav-logo">${domain^^}</div>
        <div class="nav-links"><a href="/">Home</a><a href="/about/">About</a><a href="/contact/">Contact</a><a href="/blog/">Blog</a></div>
    </div>
</nav>
<div class="container">
    <div class="post-meta"><span id="postDate"></span> · 5 min read</div>
    <h1>Security Update: Enhanced DDoS Mitigation Layer</h1>
    <div class="content">
        <p>We are pleased to announce the deployment of a new, advanced DDoS mitigation layer across our global edge network. This update brings several key improvements to our security infrastructure.</p>
        <p><strong>Key enhancements include:</strong></p>
        <ul style="margin-left: 1.5rem;">
            <li>Real-time traffic analysis with machine learning</li>
            <li>Sub-second attack detection and response</li>
            <li>Enhanced TLS fingerprinting protection</li>
            <li>Rate limiting at the network edge</li>
        </ul>
        <p>These improvements are already active for all customers and require no configuration changes on your end. The new system has successfully mitigated several large-scale attacks over the past week with zero customer impact.</p>
    </div>
    <div class="footer"><div>© <span id="year"></span> ${domain} · Enterprise Infrastructure</div></div>
</div>
<script>
    document.getElementById('year').textContent = new Date().getFullYear();
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    const now = new Date();
    document.getElementById('postDate').textContent = months[now.getMonth()] + ' ' + now.getFullYear();
</script>
</body>
</html>
EOF

    # =====================================
    # Blog post 2
    # =====================================
    cat > /var/www/html/blog/network-expansion.html << EOF
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Network Expansion | ${domain^^}</title>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: 'Segoe UI', system-ui, sans-serif;
        background: radial-gradient(ellipse at 20% 30%, #0a0f1a, #03060c);
        color: #e2e8f0;
    }
    .navbar {
        position: fixed;
        top: 0;
        width: 100%;
        background: rgba(15, 23, 42, 0.9);
        backdrop-filter: blur(12px);
        border-bottom: 1px solid rgba(56, 189, 248, 0.2);
        padding: 1rem 2rem;
        z-index: 100;
    }
    .nav-container {
        max-width: 1200px;
        margin: 0 auto;
        display: flex;
        justify-content: space-between;
        align-items: center;
        flex-wrap: wrap;
        gap: 1rem;
    }
    .nav-logo {
        font-size: 1.5rem;
        font-weight: 700;
        background: linear-gradient(135deg, #38bdf8, #a855f7);
        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
    }
    .nav-links { display: flex; gap: 2rem; flex-wrap: wrap; }
    .nav-links a { color: #cbd5e1; text-decoration: none; font-size: 0.9rem; }
    .nav-links a:hover { color: #38bdf8; }
    .container { max-width: 900px; margin: 0 auto; padding: 8rem 2rem 3rem; }
    .post-meta { color: #38bdf8; font-size: 0.8rem; margin-bottom: 1rem; }
    h1 { font-size: 2rem; margin-bottom: 1rem; }
    .content { line-height: 1.8; color: #94a3b8; }
    .content p { margin-bottom: 1rem; }
    .footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid rgba(255,255,255,0.1); text-align: center; font-size: 0.7rem; color: #475569; }
</style>
</head>
<body>
<nav class="navbar">
    <div class="nav-container">
        <div class="nav-logo">${domain^^}</div>
        <div class="nav-links"><a href="/">Home</a><a href="/about/">About</a><a href="/contact/">Contact</a><a href="/blog/">Blog</a></div>
    </div>
</nav>
<div class="container">
    <div class="post-meta"><span id="postDate"></span> · 3 min read</div>
    <h1>Global Network Expansion: 15 New Edge Locations</h1>
    <div class="content">
        <p>Today we announce a major expansion of our global edge network. With new points of presence in key markets, we continue to reduce latency and improve reliability for our customers worldwide.</p>
        <p><strong>New edge locations now online:</strong></p>
        <ul style="margin-left: 1.5rem;">
            <li>São Paulo, Brazil</li>
            <li>Mumbai, India</li>
            <li>Seoul, South Korea</li>
            <li>Sydney, Australia</li>
            <li>Warsaw, Poland</li>
        </ul>
        <p>This expansion represents a 40% increase in our global capacity and brings total edge locations to over 50 worldwide. Customers in these regions will see reduced latency and improved throughput immediately.</p>
    </div>
    <div class="footer"><div>© <span id="year"></span> ${domain} · Enterprise Infrastructure</div></div>
</div>
<script>document.getElementById('year').textContent = new Date().getFullYear();</script>
</body>
</html>
EOF

    # =====================================
    # News page
    # =====================================
    cat > /var/www/html/news/edge-location.html << EOF
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>New Edge Location | ${domain^^}</title>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: 'Segoe UI', system-ui, sans-serif;
        background: radial-gradient(ellipse at 20% 30%, #0a0f1a, #03060c);
        color: #e2e8f0;
    }
    .navbar {
        position: fixed;
        top: 0;
        width: 100%;
        background: rgba(15, 23, 42, 0.9);
        backdrop-filter: blur(12px);
        border-bottom: 1px solid rgba(56, 189, 248, 0.2);
        padding: 1rem 2rem;
        z-index: 100;
    }
    .nav-container {
        max-width: 1200px;
        margin: 0 auto;
        display: flex;
        justify-content: space-between;
        align-items: center;
        flex-wrap: wrap;
        gap: 1rem;
    }
    .nav-logo {
        font-size: 1.5rem;
        font-weight: 700;
        background: linear-gradient(135deg, #38bdf8, #a855f7);
        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
    }
    .nav-links { display: flex; gap: 2rem; flex-wrap: wrap; }
    .nav-links a { color: #cbd5e1; text-decoration: none; font-size: 0.9rem; }
    .nav-links a:hover { color: #38bdf8; }
    .container { max-width: 900px; margin: 0 auto; padding: 8rem 2rem 3rem; }
    .post-meta { color: #38bdf8; font-size: 0.8rem; margin-bottom: 1rem; }
    h1 { font-size: 2rem; margin-bottom: 1rem; }
    .content { line-height: 1.8; color: #94a3b8; }
    .footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid rgba(255,255,255,0.1); text-align: center; font-size: 0.7rem; color: #475569; }
</style>
</head>
<body>
<nav class="navbar">
    <div class="nav-container">
        <div class="nav-logo">${domain^^}</div>
        <div class="nav-links"><a href="/">Home</a><a href="/about/">About</a><a href="/contact/">Contact</a><a href="/blog/">Blog</a></div>
    </div>
</nav>
<div class="container">
    <div class="post-meta"><span id="postDate"></span> · 4 min read</div>
    <h1>New Edge Location: Asia-Pacific Region</h1>
    <div class="content">
        <p>We are excited to announce the launch of our newest edge location in Singapore. This expanded presence in the Asia-Pacific region provides our customers with lower latency and improved performance across Southeast Asia and Oceania.</p>
        <p>The new facility features redundant power, multiple carrier connections, and direct peering with major regional networks. Customers can expect up to 45% reduction in latency for traffic originating in the region.</p>
        <p>This location is now fully operational and accepting traffic. Please contact our sales team for specific connectivity options and custom peering arrangements.</p>
    </div>
    <div class="footer"><div>© <span id="year"></span> ${domain} · Enterprise Infrastructure</div></div>
</div>
<script>document.getElementById('year').textContent = new Date().getFullYear();</script>
</body>
</html>
EOF

    green "Complete website structure created for domain $domain"
    green "- Main page: index.html"
    green "- About page: /about/index.html"
    green "- Contact page: /contact/index.html"
    green "- Blog posts: /blog/security-update-2026.html, /blog/network-expansion.html"
    green "- News: /news/edge-location.html"
    green "- robots.txt and sitemap.xml"
}

# =====================================
# Function: Show installation checklist
# =====================================
show_install_checklist() {
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                    INSTALLATION CHECKLIST"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Caddy
    if systemctl is-active --quiet caddy; then
        green "✓ Caddy service: running"
    else
        red "✗ Caddy service: NOT running"
    fi
    
    # Ports
	ss -tlnp | grep -q ":$SSH_PORT " && green "✓ Port $SSH_PORT (SSH): listening" || yellow "○ Port $SSH_PORT (SSH): not listening"
    ss -tlnp | grep -q ":80 " && green "✓ Port 80: listening" || green "○ Port 80: not listening"
    ss -tlnp | grep -q ":443 " && green "✓ Port 443: listening" || green "○ Port 443: not listening"
    
    # Firewall (UFW for Debian/Ubuntu, firewalld for RHEL)
    case $SYSTEM in
        "Debian"|"Ubuntu")
            if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
                ufw status | grep -q "$SSH_PORT/tcp.*ALLOW" && green "✓ UFW: port $SSH_PORT (SSH) allowed" || yellow "○ UFW: port $SSH_PORT (SSH) rule missing"
                ufw status | grep -q "80/tcp.*ALLOW" && green "✓ UFW: port 80 allowed" || yellow "○ UFW: port 80 rule missing"
                ufw status | grep -q "443/tcp.*ALLOW" && green "✓ UFW: port 443 allowed" || yellow "○ UFW: port 443 rule missing"
            else
                yellow "○ UFW: not active"
            fi
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
                if firewall-cmd --list-ports 2>/dev/null | grep -q "$SSH_PORT/tcp"; then
                    green "✓ firewalld: port $SSH_PORT (SSH) allowed"
                else
                    yellow "○ firewalld: port $SSH_PORT (SSH) not allowed"
                fi
                if firewall-cmd --list-ports 2>/dev/null | grep -q "80/tcp"; then
                    green "✓ firewalld: port 80 allowed"
                else
                    yellow "○ firewalld: port 80 not allowed"
                fi
                if firewall-cmd --list-ports 2>/dev/null | grep -q "443/tcp"; then
                    green "✓ firewalld: port 443 allowed"
                else
                    yellow "○ firewalld: port 443 not allowed"
                fi
            else
                yellow "○ firewalld: not active"
            fi
            ;;
        *)
            yellow "○ Firewall: unknown system"
            ;;
    esac
    
    # SSL Certificate
    CERT_FILE=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    if [[ -n "$CERT_FILE" ]]; then
        CERT_EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)
        green "✓ SSL certificate: valid until ${CERT_EXPIRY}"
    else
        red "✗ SSL certificate: not obtained"
    fi
    
    # Client configs
    [[ -f /root/naive/naive-client.json ]] && green "✓ Client config: /root/naive/naive-client.json" || red "✗ Client config: missing"
    [[ -f /root/naive/naive-url.txt ]] && green "✓ Import link: /root/naive/naive-url.txt" || red "✗ Import link: missing"
    
    # fail2ban
    if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban; then
        green "✓ fail2ban: active"
    else
        yellow "○ fail2ban: not active"
    fi
    
    # BBR
    sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr" && green "✓ BBR: enabled" || yellow "○ BBR: not enabled"
    
    # External connectivity
    SERVER_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "unknown")
    if [[ "$SERVER_IP" != "unknown" ]]; then
        if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/443" 2>/dev/null; then
            green "✓ Port 443: reachable from internet"
        else
            red "✗ Port 443: not reachable"
        fi
    else
        yellow "○ Could not determine external IP"
    fi
    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
}

# =====================================
# Function: Wait for SSL certificate
# =====================================
wait_for_ssl_certificate() {
    local domain=$1
    local max_wait=60
    local waited=0
    
    CERT_DIRS=(
        "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$domain"
        "/var/lib/caddy/.local/share/caddy/certificates/acme.zerossl.com-v2-DV90/$domain"
        "/root/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$domain"
        "/root/.local/share/caddy/certificates/acme.zerossl.com-v2-DV90/$domain"
    )
    
    while [[ $waited -lt $max_wait ]]; do
        for cert_dir in "${CERT_DIRS[@]}"; do
            if [[ -f "$cert_dir/$domain.crt" ]] && [[ -f "$cert_dir/$domain.key" ]]; then
                return 0
            fi
        done
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# =====================================
# Function: NaiveProxy Installation (Basic)
# =====================================
install_naiveproxy() {
    green "I'm starting the installation of NaiveProxy ..."
    
    yellow "\nChecking system requirements ..."
    check_system_requirements
    check_hardware_requirements
    setup_swap 
    install_base_packages
    setup_auto_updates
    increase_limits
    optimize_sysctl
    disable_unnecessary_services
    install_go
    build_caddy
    input_parameters
	change_ssh_port
    setup_fail2ban
    configure_firewall
    
    mkdir -p /etc/caddy /var/www/html
    create_landing_page
    create_configs
    create_systemd_service
    enable_bbr

    if systemctl is-active --quiet caddy; then
        green "\nNaiveProxy is successfully installed and running!"
        echo "The client configuration is saved in /root/naive/"
        show_config
        wait_for_ssl_certificate "$domain"
        show_install_checklist 
        
        # SSH port change warning
        if [[ $SSH_PORT -ne $CURRENT_SSH_PORT ]]; then
            echo ""
            yellow "═══════════════════════════════════════════════════════════════"
            yellow "                   SSH PORT CHANGED"
            yellow "═══════════════════════════════════════════════════════════════"
            echo ""
            yellow "○ SSH port has been changed from $CURRENT_SSH_PORT to $SSH_PORT"
            yellow "○ Your current connection remains active on port $CURRENT_SSH_PORT"
            echo ""
            red "✗ NEXT TIME CONNECT USING:"
            red "    ssh -p $SSH_PORT root@$SERVER_IP"
            echo ""
            yellow "○ Make sure your firewall allows port $SSH_PORT"
            yellow "○ If you lose access, use VPS console to check"
            echo ""
            yellow "═══════════════════════════════════════════════════════════════"
        fi
    else
        red "Error starting Caddy! Check the logs: journalctl -u caddy -n 50"
        exit 1
    fi
}

# =====================================
# Function: Remove NaiveProxy
# =====================================
uninstall_naiveproxy() {
    yellow "Removing NaiveProxy ..."
    
    systemctl stop caddy 2>/dev/null
    systemctl disable caddy 2>/dev/null
    
    rm -rf /etc/caddy /root/naive /usr/bin/caddy /etc/systemd/system/caddy.service
    rm -rf /root/go /root/tmp
    
    sed -i '/export PATH=\$PATH:\/usr\/local\/go\/bin/d' ~/.bashrc
    
    systemctl daemon-reload
    
    green "NaiveProxy has been completely removed!"
    echo -e "${YELLOW}Note:${PLAIN} Go (/usr/local/go) was not removed to avoid damaging other possible projects"
    echo -e "If you want to remove Go, run the command: ${YELLOW}rm -rf /usr/local/go${PLAIN}"
}

# =====================================
# Function: Installation Check
# =====================================
is_naive_installed() {
    [[ -f /usr/bin/caddy ]] && [[ -f /etc/systemd/system/caddy.service ]] && [[ -f /root/naive/naive-client.json ]]
    return $?
}

# =====================================
# Function: Run proxy
# =====================================
start_naiveproxy() {
    if ! is_naive_installed; then
        yellow "NaiveProxy is not installed! Please install it first (step 1)"
        return 0
    fi
    systemctl start caddy
    systemctl enable caddy 2>/dev/null
    green "NaiveProxy is launched"
}

# =====================================
# Function: Stop proxy
# =====================================
stop_naiveproxy() {
    if ! is_naive_installed; then
        yellow "NaiveProxy is not installed"
        return 0
    fi
    systemctl stop caddy
    green "NaiveProxy has stopped"
}

# =====================================
# Function: Restart proxy
# =====================================
restart_naiveproxy() {
    if ! is_naive_installed; then
        yellow "NaiveProxy is not installed! Please install it first (step 1)"
        return 0
    fi
    systemctl restart caddy
    green "NaiveProxy has been relaunched"
}

# =====================================
# Function: Show client configuration
# =====================================
show_config() {
    if ! is_naive_installed; then
        yellow "NaiveProxy is not installed! Please install it first (step 1)"
        echo ""
        return 0
    fi
    
	echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                    CLIENT CONFIGURATION"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
	
    echo -e "${GREEN}JSON format:${PLAIN}"
	echo ""
    cat /root/naive/naive-client.json
    echo ""
    echo -e "${GREEN}Import link:${PLAIN}"
	echo ""
    cat /root/naive/naive-url.txt
    echo ""
	echo -e "${GREEN}Server:${PLAIN}    $domain"
    echo -e "${GREEN}Port:${PLAIN}      $proxyport"
    echo -e "${GREEN}Username:${PLAIN}  $proxyname"
    echo -e "${GREEN}Password:${PLAIN}  $proxypwd"
	echo ""
	yellow "═══════════════════════════════════════════════════════════════"
	echo ""
    if command -v qrencode &>/dev/null; then
        green "QR code for importing to your smartphone:"
        echo ""
        qrencode -t ANSIUTF8 "$(cat /root/naive/naive-url.txt)" 2>/dev/null || yellow "QR code generation error"
    fi
    echo ""
}

# =====================================
# Function: Main Menu
# =====================================
show_menu() {
    clear	
	
    echo "#################################################"
    echo -e "--${GREEN}NaiveProxy Installer${PLAIN}-------------------${BLUE}Kordan${PLAIN}--"
    echo "#################################################"
	echo ""
	check_system_requirements
    echo " ----------------"
    echo -e " ${GREEN}1.${PLAIN} Install"
    echo -e " ${RED}2.${PLAIN} Uninstall"
    echo " ----------------"
    echo -e " ${GREEN}3.${PLAIN} Start"
    echo -e " ${GREEN}4.${PLAIN} Stop"
    echo -e " ${GREEN}5.${PLAIN} Restart"
    echo " ----------------"
    echo -e " ${GREEN}6.${PLAIN} Client config"
    echo " -------------"
    echo -e " ${GREEN}7.${PLAIN} System info"
	echo -e " ${GREEN}8.${PLAIN} System maintenance"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} Exit"
    echo ""
	echo "#################################################"
    
    local attempts=0
    local max_attempts=3
    
    while true; do
        if [[ $attempts -ge $max_attempts ]]; then
            red "\nMaximum attempts $max_attempts exceeded. Exiting"
            exit 1
        fi
		
        echo ""
        read -rp " Your choice [0-8]: " answer
        
        if [[ -z "$answer" ]]; then
            attempts=$((attempts + 1))
            yellow "Error: Enter a number from 0 to 8. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if ! echo "$answer" | grep -qE '^[0-9]+$'; then
            attempts=$((attempts + 1))
            yellow "Error: Enter a number. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if [[ $answer -lt 0 ]] || [[ $answer -gt 8 ]]; then
            attempts=$((attempts + 1))
            yellow "Error: Number must be between 0 and 8. Attempt $attempts of $max_attempts"
            continue
        fi
        
        break
    done
    
    case $answer in
        1) install_naiveproxy ;;
        2) uninstall_naiveproxy ;;
        3) start_naiveproxy ;;
        4) stop_naiveproxy ;;
        5) restart_naiveproxy ;;
        6) show_config ;;
		7) show_system_info ;;
		8) system_maintenance ;;
        0) clear && exit 0 ;;
    esac
    
    if [[ $answer != "0" ]]; then
        echo ""
        read -rp "Press Enter to return to the menu ..."
        show_menu
    fi
}

# =====================================
# Start script
# =====================================
show_menu
