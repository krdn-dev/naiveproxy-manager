#!/bin/bash
# ===========================================================================
# Name:         NaiveProxy Secure Installer
# Description:  The most advanced NaiveProxy installer — auto‑swap, fail2ban, 
#               BBR, rate limiting, corporate site simulation, QR configs. 
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
# Definition of the system
# =====================================
REGEX=("debian" "ubuntu" "centos|red hat|kernel" "oracle linux" "alma" "rocky" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "Oracle Linux" "AlmaLinux" "Rocky Linux" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "yum -y install" "yum -y install")

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
    
    green "System: $SYSTEM $VERSION (supported)"
}

# =====================================
# Function: Configure automatic updates based on OS
# =====================================
setup_auto_updates() {
    yellow "Setting up automatic security updates ..."
    
    case $SYSTEM in
        "Debian"|"Ubuntu")
            ${PACKAGE_INSTALL[int]} unattended-upgrades -y 2>/dev/null
            cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
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
    yellow "Configuring fail2ban to protect SSH ..."
    
    # Determine the current SSH port
    SSH_PORT=$(ss -tlnp | grep -oP '(?<=:)\d+(?=.*sshd)' | head -n1)
    [[ -z "$SSH_PORT" ]] && SSH_PORT=22
    
    # # ----- For CentOS/RHEL/Alma/Rocky, enable EPEL (needed for qrencode and fail2ban) -----
	if [[ $SYSTEM == "CentOS" ]] || [[ $SYSTEM == "Fedora" ]] || [[ $SYSTEM == "AlmaLinux" ]] || [[ $SYSTEM == "Rocky Linux" ]]; then
		if ! rpm -q epel-release &>/dev/null && ! rpm -q epel-next-release &>/dev/null; then
			yellow "Connecting the EPEL repository for fail2ban ..."
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
        green "fail2ban is activated (protection against password guessing)"
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

# =====================================
# Function: Install base packages
# =====================================
install_base_packages() {
    yellow "Installing base packages ..."
    
    # ----- Updating the package list (carefully for CentOS) -----
    if [[ $SYSTEM == "CentOS" ]] && [[ ${VERSION:-0} -ge 8 ]]; then
        ${PACKAGE_UPDATE[int]} 2>/dev/null || true
    elif [[ $SYSTEM != "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    
    # ----- For CentOS/RHEL/Alma/Rocky, enable EPEL (needed for qrencode and fail2ban) -----
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
    
    # ----- Entering port -----
    while true; do    
        echo ""
        blue "→ Port selection:"
        echo "  [1] 443  (Recommended — best camouflage)"
        echo "  [2] 8443 (Alternative — often allowed in corporate networks)"
        echo "  [3] Custom port (range 1024-65535)"
        echo ""
        read -rp "$(green "Your choice [1-2-3]: ")" port_choice

        case $port_choice in
            1)
                proxyport=443
                green "✓ Port 443 selected"
                break
                ;;
            2)
                proxyport=8443
                green "✓ Port 8443 selected"
                break
                ;;
            3)
                read -rp "$(yellow "Enter custom port (1024-65535): ")" proxyport
                if [[ "$proxyport" =~ ^[0-9]+$ ]] && [ "$proxyport" -ge 1024 ] && [ "$proxyport" -le 65535 ]; then
                    green "✓ Port $proxyport selected"
                    break
                else
                    red "✗ Error: Invalid port — must be number between 1024 and 65535"
                fi
                ;;
            *)
                red "✗ Invalid choice — please select 1, 2, or 3"
                ;;
        esac
    done

    # ----- Checking port occupancy -----
    if ss -tlnp | grep -q ":$proxyport "; then
        red "✗ Port $proxyport is already in use by another process!"
        exit 1
    fi

    green "✓ Port $proxyport is free and available"
    echo ""

    # ----- Entering a domain -----
    while true; do
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
    echo ""

    # ----- Entering email -----
    while true; do
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
    echo ""

    # ----- Entering username -----
    while true; do
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
    echo ""

    # ----- Entering a password -----
    while true; do
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
    yellow "═══════════════════════════════════════════════════════════════"
    green "✓ Configuration completed successfully!"
    yellow "═══════════════════════════════════════════════════════════════"
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
    
    # Rate limiting — защита от DDoS и перебора
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
# NaiveProxy optimizations
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.ip_local_port_range = 1024 65535
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
  <url><loc>https://${domain}/blog/security-update-2026</loc><lastmod>2026-04-28</lastmod><changefreq>weekly</changefreq><priority>0.6</priority></url>
  <url><loc>https://${domain}/blog/network-expansion</loc><lastmod>2026-04-20</lastmod><changefreq>weekly</changefreq><priority>0.6</priority></url>
  <url><loc>https://${domain}/news/edge-location</loc><lastmod>2026-04-10</lastmod><changefreq>weekly</changefreq><priority>0.6</priority></url>
</urlset>
EOF

    # =====================================
    # Main index.html
    # =====================================
    cat > /var/www/html/index.html << 'EOF'
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
        <div class="nav-logo">'${domain^^}'</div>
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
        <div class="logo">'${domain^^}'</div>
        <div class="subtitle">Enterprise Infrastructure</div>
    </div>

    <div class="card">
        <div class="status-badge">
            <span class="status-dot"></span>
            <span>System Online | HA Cluster Active</span>
        </div>
        <h2>Corporate Portal</h2>
        <p>Welcome to the '${domain}' corporate portal. High-availability infrastructure with geographic redundancy, DDoS protection, and real-time monitoring across all edge locations.</p>
    </div>

    <div class="features-grid">
        <div class="feature-item"><span class="feature-icon">🚀</span><div class="feature-title">Edge Network</div><div class="feature-desc">Global anycast routing</div></div>
        <div class="feature-item"><span class="feature-icon">🛡️</span><div class="feature-title">Advanced Security</div><div class="feature-desc">WAF + DDoS mitigation</div></div>
        <div class="feature-item"><span class="feature-icon">🌍</span><div class="feature-title">Geo-redundancy</div><div class="feature-desc">Multi-region failover</div></div>
        <div class="feature-item"><span class="feature-icon">⚡</span><div class="feature-title">99.99% Uptime</div><div class="feature-desc">SLA guaranteed</div></div>
    </div>

    <div class="blog-grid">
        <div class="blog-card"><div class="blog-date"><span id="blogDate1"></span></div><div class="blog-title">Infrastructure Upgrade Complete</div><div class="blog-excerpt">All systems are now running on the latest hardware revision.</div><a href="/blog/security-update-2026" class="read-more">Read more →</a></div>
        <div class="blog-card"><div class="blog-date"><span id="blogDate2"></span></div><div class="blog-title">New DDoS Protection Layer</div><div class="blog-excerpt">Enhanced mitigation capabilities now active across all edge nodes.</div><a href="/blog/network-expansion" class="read-more">Read more →</a></div>
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
        <div>© <span id="currentYear"></span> '${domain}' · Enterprise Infrastructure · All rights reserved</div>
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
    cat > /var/www/html/about/index.html << 'EOF'
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
        <div class="nav-logo">'${domain^^}'</div>
        <div class="nav-links"><a href="/">Home</a><a href="/about/">About</a><a href="/contact/">Contact</a><a href="/blog/">Blog</a></div>
    </div>
</nav>
<div class="container">
    <h1>About '${domain}'</h1>
    <div class="card">
        <p><strong>'${domain}' Infrastructure</strong> is a global edge network provider delivering high-performance, secure, and reliable connectivity solutions for enterprises worldwide.</p>
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
    <div class="footer"><div>© <span id="year"></span> '${domain}' · Enterprise Infrastructure</div></div>
</div>
<script>document.getElementById('year').textContent = new Date().getFullYear();</script>
</body>
</html>
EOF

    # =====================================
    # Contact page
    # =====================================
    cat > /var/www/html/contact/index.html << 'EOF'
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
        <div class="nav-logo">'${domain^^}'</div>
        <div class="nav-links"><a href="/">Home</a><a href="/about/">About</a><a href="/contact/">Contact</a><a href="/blog/">Blog</a></div>
    </div>
</nav>
<div class="container">
    <h1>Contact '${domain}'</h1>
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
    <div class="footer"><div>© <span id="year"></span> '${domain}' · Enterprise Infrastructure</div></div>
</div>
<script>document.getElementById('year').textContent = new Date().getFullYear();</script>
</body>
</html>
EOF

    # =====================================
    # Blog post 1
    # =====================================
    cat > /var/www/html/blog/security-update-2026.html << 'EOF'
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
        <div class="nav-logo">'${domain^^}'</div>
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
    <div class="footer"><div>© <span id="year"></span> '${domain}' · Enterprise Infrastructure</div></div>
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
    cat > /var/www/html/blog/network-expansion.html << 'EOF'
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
        <div class="nav-logo">'${domain^^}'</div>
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
    <div class="footer"><div>© <span id="year"></span> '${domain}' · Enterprise Infrastructure</div></div>
</div>
<script>document.getElementById('year').textContent = new Date().getFullYear();</script>
</body>
</html>
EOF

    # =====================================
    # News page
    # =====================================
    cat > /var/www/html/news/edge-location.html << 'EOF'
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
        <div class="nav-logo">'${domain^^}'</div>
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
    <div class="footer"><div>© <span id="year"></span> '${domain}' · Enterprise Infrastructure</div></div>
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
    setup_fail2ban
	increase_limits
    optimize_sysctl
    disable_unnecessary_services
    install_go
    build_caddy
    input_parameters
    
    mkdir -p /etc/caddy /var/www/html
	create_landing_page
    create_configs
    create_systemd_service
    enable_bbr

    if systemctl is-active --quiet caddy; then
        green "\nNaiveProxy is successfully installed and running!"
        echo "The client configuration is saved in /root/naive/"
        show_config
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
    
    yellow "\n=== Client Configuration ==="
    echo -e "${GREEN}JSON format (file: /root/naive/naive-client.json):${PLAIN}"
    cat /root/naive/naive-client.json
    echo ""
    echo -e "${GREEN}Import link (file: /root/naive/naive-url.txt):${PLAIN}"
    cat /root/naive/naive-url.txt
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
    echo -e " ${GREEN}1.${PLAIN} Install NaiveProxy"
    echo -e " ${RED}2.${PLAIN} Uninstall NaiveProxy"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} Start NaiveProxy"
    echo -e " ${GREEN}4.${PLAIN} Stop NaiveProxy"
    echo -e " ${GREEN}5.${PLAIN} Restart NaiveProxy"
    echo " -------------"
    echo -e " ${GREEN}6.${PLAIN} Show client config"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} Exit"
    echo ""
    
    local attempts=0
    local max_attempts=3
    
    while true; do
        if [[ $attempts -ge $max_attempts ]]; then
            red "\nMaximum attempts $max_attempts exceeded. Exiting"
            exit 1
        fi
        
        read -rp " Your choice [0-6]: " answer
        
        if [[ -z "$answer" ]]; then
            attempts=$((attempts + 1))
            yellow "Error: Enter a number from 0 to 6. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if ! echo "$answer" | grep -qE '^[0-9]+$'; then
            attempts=$((attempts + 1))
            yellow "Error: Enter a number. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if [[ $answer -lt 0 ]] || [[ $answer -gt 6 ]]; then
            attempts=$((attempts + 1))
            yellow "Error: Number must be between 0 and 6. Attempt $attempts of $max_attempts"
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
check_system_requirements
show_menu
