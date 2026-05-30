#!/bin/bash
# ===========================================================================
# Name:         NaiveProxy Manager
# Description:  One‑command NaiveProxy Manager with realistic traffic camouflage
#				– corporate website, visitor simulation, mutual imitation,
#				scanner noise. Works on 7 Linux distros
# Author:       Kordan (krdn-dev)
# GitHub:       https://github.com/krdn-dev/naiveproxy-manager
# License:      MIT
# ===========================================================================

export LANG=en_US.UTF-8

# =====================================
# Colors and styles
# =====================================
RED="\033[91m"
GREEN="\033[38;5;46m"
YELLOW="\033[33m"
BLUE="\033[94m"
PLAIN="\033[0m"

red() { echo -e "${RED}${1}${PLAIN}"; }
green() { echo -e "${GREEN}${1}${PLAIN}"; }
yellow() { echo -e "${YELLOW}${1}${PLAIN}"; }
blue() { echo -e "${BLUE}${1}${PLAIN}"; }

# =====================================
# Global variables
# =====================================
remote_server=""
ssh_port=22
os_idx=0
proxyport=""
proxyname=""
proxypwd=""
domain=""
email=""

# =====================================
# Definition of the system
# =====================================
REGEX=("debian" "ubuntu" "centos|red hat|kernel" "oracle linux" "alma" "rocky" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "Oracle Linux" "AlmaLinux" "Rocky Linux" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "yum -y install" "yum -y install")

# =====================================
# Package lists for easier maintenance
# =====================================
# Essential tools (curl, wget, openssl, tar) - used in install_essential_tools
readonly ESSENTIAL_CMDS=("curl" "wget" "openssl" "tar")

# Common packages for all systems
COMMON_PACKAGES=("git" "sudo" "dos2unix" "qrencode" "bc" "shellcheck")

# Debian/Ubuntu specific packages
DEBIAN_PACKAGES=("dnsutils" "build-essential")

# RHEL/CentOS/Fedora/Alma/Rocky/Oracle specific packages
RHEL_PACKAGES=("epel-release" "bind-utils" "gcc" "gcc-c++" "make")

# =====================================
# Function: Quote string for safe insertion into shell config file
# Parameters: $1 - string to quote
# Returns: quoted string (single-quoted with internal single quotes escaped)
# =====================================
shell_quote() {
    printf "%q" "$1"
}

# =====================================
# Function: Install precompiled WebGhost binary + full setup
# =====================================
install_webghost() {
    yellow "  Installing WebGhost (precompiled binary) ..."

    # Создаём необходимые директории
    mkdir -p /etc/caddy /var/www/html
    chmod -R 755 /var/www/html

    # Доставка бинарника
    if [[ ! -f /usr/local/bin/webghost ]]; then
        local script_dir
		script_dir="$(cd "$(dirname "$0")" && pwd)"
        if [[ -f "$script_dir/webghost" ]]; then
            cp "$script_dir/webghost" /usr/local/bin/webghost
            chmod +x /usr/local/bin/webghost
            green "✓ Installed WebGhost from local directory"
        else
            # ---- Проверка архитектуры ----
            local arch
			arch="$(uname -m)"
            if [[ "$arch" != "x86_64" ]]; then
                yellow "○ WebGhost binary is built for x86_64, but your architecture is ${arch}"
                yellow "  The binary will likely NOT work on this system"
                read -rp "  Continue anyway? [y/N]: " cont_anyway
                if [[ ! "$cont_anyway" =~ ^[Yy]$ ]]; then
                    red "  Installation aborted."
                    return 1
                fi
            fi
            
            local download_url="https://github.com/krdn-dev/webghost/releases/latest/download/webghost-linux-amd64"
            yellow "  Downloading WebGhost from ${download_url} ..."
            
            # Скачиваем с проверкой ошибок и индикацией прогресса
            if ! curl -L --progress-bar --fail -o /usr/local/bin/webghost "$download_url" 2>/dev/null; then
                red "✗ Failed to download WebGhost"
                red "✗ Please place webghost binary in /usr/local/bin/ and rerun the installer"
                return 1
            fi
            
            # Дополнительная проверка, что файл не пустой
            if [[ ! -s /usr/local/bin/webghost ]]; then
                red "✗ Downloaded file is empty"
                rm -f /usr/local/bin/webghost
                return 1
            fi
            
            chmod +x /usr/local/bin/webghost
            green "✓ WebGhost installed to /usr/local/bin/webghost"
        fi
    else
        green "✓ WebGhost already installed"
    fi

    # Проверяем, что бинарник исполняемый
    if [[ ! -x /usr/local/bin/webghost ]]; then
        red "✗ WebGhost binary is not executable"
        return 1
    fi

    # Запуск webghost install (сайт + systemd-таймер)
    yellow "  Setting up website and traffic simulation timer ..."
    local args=("$domain")
    [[ -n "${remote_server:-}" ]] && args+=("$remote_server")
    args+=(install --post --quiet)

    # Временный лог-файл для диагностики
    local webghost_log="/tmp/webghost-install-$$.log"
    
    # Запускаем webghost с таймаутом 60 секунд и сохраняем вывод в лог
    timeout 60 /usr/local/bin/webghost "${args[@]}" > "$webghost_log" 2>&1 &
    local webghost_pid=$!
    
    # Ожидаем появления таймера (максимум 30 секунд)
    local waited=0
    local max_wait=30
    echo -n "  Waiting for timer to be created"
    
    while [[ $waited -lt $max_wait ]]; do
        # Проверяем, не завершился ли процесс webghost досрочно с ошибкой
        if ! kill -0 "$webghost_pid" 2>/dev/null; then
            wait "$webghost_pid"
            local exit_code=$?
            if [[ $exit_code -ne 0 ]]; then
                echo ""
                red "✗ WebGhost install failed with exit code $exit_code"
                yellow "  Log: $webghost_log"
                head -20 "$webghost_log" | sed 's/^/    /'
                rm -f "$webghost_log"
                return 1
            fi
        fi
        
        # Проверяем наличие таймера
        if systemctl list-unit-files 2>/dev/null | grep -q "webghost-activity.timer"; then
            echo ""
            green "✓ WebGhost timer detected"
            # Включаем и запускаем таймер (на случай, если он не активирован)
            systemctl enable --now webghost-activity.timer 2>/dev/null
            green "✓ WebGhost: website and traffic simulation started"
            green "✓ Log file: /var/log/webghost-activity.log"
            rm -f "$webghost_log"
            return 0
        fi
        
        sleep 1
        waited=$((waited + 1))
        echo -n "."
    done
    
    # Таймер не появился за отведённое время
    echo ""
    red "✗ WebGhost timer not created within ${max_wait} seconds"
    
    # Проверяем, жив ли ещё процесс webghost
    if kill -0 "$webghost_pid" 2>/dev/null; then
        yellow "  WebGhost process (PID $webghost_pid) is still running, but timer missing"
        yellow "  Killing it to avoid orphaned process"
        kill "$webghost_pid" 2>/dev/null
        sleep 1
        kill -9 "$webghost_pid" 2>/dev/null
    fi
    
    yellow "  Installation log: $webghost_log"
    if [[ -s "$webghost_log" ]]; then
        yellow "  Last 10 lines of output:"
        tail -10 "$webghost_log" | sed 's/^/    /'
    fi
    
    return 1
}

# =====================================
# Function: Save runtime configuration (safe for source)
# =====================================
save_runtime_config() {
    mkdir -p /root/naive

    # Функция для экранирования строки для использования в кавычках
    # Экранирует " \ $ ` и (опционально) другие спецсимволы
    _escape_for_source() {
        local input="$1"
        # Заменяем \ на \\, " на \", $ на \$, ` на \`
        input=$(printf '%s' "$input" | sed 's/[\\"$`]/\\&/g')
        printf '%s' "$input"
    }

    local safe_proxyport
	safe_proxyport="$(_escape_for_source "$proxyport")"
	local safe_proxyname
	safe_proxyname="$(_escape_for_source "$proxyname")"
	local safe_proxypwd	
    safe_proxypwd="$(_escape_for_source "$proxypwd")"
	local safe_domain
    safe_domain="$(_escape_for_source "$domain")"
	local safe_email
    safe_email="$(_escape_for_source "$email")"
	local safe_ssh_port
    safe_ssh_port="$(_escape_for_source "$ssh_port")"
	local safe_remote_server
    safe_remote_server="$(_escape_for_source "${remote_server:-}")"

    cat > /root/naive/runtime.env << EOF
# NaiveProxy Runtime Configuration - DO NOT EDIT MANUALLY
# Generated: $(date)
# WARNING: This file contains sensitive data! Keep it secure
proxyport="${safe_proxyport}"
proxyname="${safe_proxyname}"
proxypwd="${safe_proxypwd}"
domain="${safe_domain}"
email="${safe_email}"
ssh_port="${safe_ssh_port}"
remote_server="${safe_remote_server}"
EOF

    chmod 600 /root/naive/runtime.env
    [[ -f /root/naive/registry.txt ]] && chmod 600 /root/naive/registry.txt
    [[ -d /root/naive/users ]] && chmod -R 700 /root/naive/users

    green "✓ Runtime configuration saved to /root/naive/runtime.env"
}

# =====================================
# Function: Load configuration
# =====================================
load_runtime_config() {
    if [[ -f /root/naive/runtime.env ]]; then
		# shellcheck source=/dev/null
        source /root/naive/runtime.env
        return 0
    fi
    return 1
}

# =====================================
# Lightweight OS detection (no exit, no root required)
# Sets global variables: SYSTEM, VERSION
# =====================================
detect_os_light() {
    local SYS=""
    local CMD=(
        "$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)"
        "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)"
        "$(lsb_release -sd 2>/dev/null)"
        "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)"
        "$(grep . /etc/redhat-release 2>/dev/null)"
        "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')"
    )
    for i in "${CMD[@]}"; do
        SYS="$i" && [[ -n $SYS ]] && break
    done

    for ((i=0; i<${#REGEX[@]}; i++)); do
        if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[i]} ]]; then
            SYSTEM="${RELEASE[i]}"
            break
        fi
    done

    [[ -z "$SYSTEM" ]] && SYSTEM="Unknown"

    # Определяем версию ДО того, как читать /etc/os-release
    case $SYSTEM in
        "Debian"|"Ubuntu")
            VERSION=$(grep -oE 'VERSION_ID="[0-9]+"' /etc/os-release 2>/dev/null | grep -oE '[0-9]+')
            [[ -z "$VERSION" ]] && VERSION=$(grep -oE 'VERSION="[0-9]+"' /etc/os-release 2>/dev/null | grep -oE '[0-9]+')
            ;;
        "CentOS"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux"|"Fedora")
            VERSION=$(grep -oE '[0-9]+' /etc/os-release 2>/dev/null | head -1)
            if [[ -z "$VERSION" ]] && [[ -f /etc/centos-release ]]; then
                VERSION=$(grep -oE '[0-9]+' /etc/centos-release 2>/dev/null | head -1)
            fi
            ;;
        *) VERSION="unknown" ;;
    esac

    if [[ -f /etc/os-release ]]; then
        OS_PRETTY_NAME=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    else
        OS_PRETTY_NAME="$SYSTEM $VERSION"
    fi
}

# =====================================
# Function: Validate loaded configuration
# =====================================
validate_config() {
    if [[ -z "$domain" ]] || [[ -z "$proxyport" ]] || [[ -z "$proxyname" ]] || [[ -z "$proxypwd" ]] || [[ -z "$email" ]]; then
        return 1
    fi
    # Проверка форматов
    if ! echo "$domain" | grep -qE '^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$'; then
        return 1
    fi
    if [[ ! "$proxyport" =~ ^[0-9]+$ ]] || [[ "$proxyport" -lt 1 ]] || [[ "$proxyport" -gt 65535 ]]; then
        return 1
    fi
    if ! echo "$email" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        return 1
    fi
    return 0
}

# =====================================
# Function: Backup certificates (complete Caddy data)
# =====================================
backup_certificates() {
    local backup_dir="/root/naive/cert-backup"
    
    mkdir -p "$backup_dir"
    
    # Загружаем конфигурацию, чтобы получить domain
    if [[ -f /root/naive/runtime.env ]]; then
		# shellcheck source=/dev/null
        source /root/naive/runtime.env
    fi
    
    # Если domain все еще пустой, пробуем извлечь из сертификата
    if [[ -z "$domain" ]]; then
        local cert_file
        cert_file=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "*.crt" 2>/dev/null | head -1)
        if [[ -n "$cert_file" ]]; then
            domain=$(openssl x509 -subject -noout -in "$cert_file" 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')
        fi
    fi
    
    if [[ -z "$domain" ]]; then
        yellow "○ Cannot determine domain for backup"
        return 1
    fi
    
    # Ищем директорию Caddy
    local caddy_data_dir=""
    if [[ -d "/var/lib/caddy/.local/share/caddy" ]]; then
        caddy_data_dir="/var/lib/caddy/.local/share/caddy"
    elif [[ -d "/root/.local/share/caddy" ]]; then
        caddy_data_dir="/root/.local/share/caddy"
    else
        yellow "○ No Caddy data directory found to backup"
        return 1
    fi
    
    local backup_file="$backup_dir/caddy_data_${domain}.tar.gz"
    
    # Проверяем, что в директории есть хотя бы один сертификат
    if ! find "$caddy_data_dir" -name "*.crt" 2>/dev/null | grep -q .; then
        yellow "○ No certificate files found in $caddy_data_dir – backup skipped"
        return 1
    fi
    
    # Бэкапим
    if tar czf "$backup_file" -C "$(dirname "$caddy_data_dir")" "$(basename "$caddy_data_dir")" 2>/dev/null; then
        if [[ -s "$backup_file" ]]; then
            green "✓ Backup created ($(du -h "$backup_file" | cut -f1))"
        else
            red "✗ Backup file is empty – something went wrong"
            rm -f "$backup_file"
            return 1
        fi
        
        cat > "$backup_dir/metadata.txt" << EOF
Domain: $domain
Backup date: $(date)
Caddy version: $(caddy version 2>/dev/null | head -1)
Backup path: $caddy_data_dir
Backup file: caddy_data_${domain}.tar.gz
EOF
        green "✓ Complete Caddy data backed up to: $backup_file"
        
        # Keep only the last 5 backups
        find "$backup_dir" -name "caddy_data_*.tar.gz" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null
        
        return 0
    else
        red "✗ Failed to backup Caddy data"
        return 1
    fi
}

# =====================================
# Function: Restore certificates from backup
# =====================================
restore_certificates() {
    local backup_dir="/root/naive/cert-backup"
    local backup_file=""
    local silent=${1:-false}
    
    # Загружаем конфигурацию для получения domain
    if [[ -f /root/naive/runtime.env ]]; then
		# shellcheck source=/dev/null
        source /root/naive/runtime.env
    fi
    
    # Ищем бэкап по домену (если известен)
    if [[ -n "$domain" ]]; then
        if [[ -f "$backup_dir/caddy_data_${domain}.tar.gz" ]]; then
            backup_file="$backup_dir/caddy_data_${domain}.tar.gz"
        elif [[ -f "$backup_dir/certs_${domain}.tar.gz" ]]; then
            backup_file="$backup_dir/certs_${domain}.tar.gz"
        fi
    fi
    
    # Если не нашли по домену, ищем любой бэкап caddy_data_ (самый свежий)
    if [[ -z "$backup_file" ]]; then
        backup_file=$(find "$backup_dir" -maxdepth 1 -name "caddy_data_*.tar.gz" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    fi
    
    # Если все еще не нашли, ищем старый формат certs_
    if [[ -z "$backup_file" ]]; then
        backup_file=$(find "$backup_dir" -maxdepth 1 -name "certs_*.tar.gz" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
    fi
    
    if [[ -z "$backup_file" ]]; then
        if [[ "$silent" != "true" ]]; then
            yellow "○ No backup file found in $backup_dir"
        fi
        return 1
    fi
    
    green "✓ Found backup: $(basename "$backup_file")"
    
    # Проверяем метаданные, если есть
    if [[ -f "$backup_dir/metadata.txt" ]]; then
        local backup_expiry
        backup_expiry=$(grep "Certificate expiry:" "$backup_dir/metadata.txt" 2>/dev/null | cut -d: -f2- | xargs)
        if [[ -n "$backup_expiry" ]]; then
            local expiry_epoch
            expiry_epoch=$(date -d "$backup_expiry" +%s 2>/dev/null)
            local now_epoch
            now_epoch=$(date +%s)
            if [[ $expiry_epoch -le $now_epoch ]]; then
                yellow "○ Backup certificate expired on $backup_expiry"
                return 1
            fi
            green "✓ Backup certificate valid until $backup_expiry"
        fi
    fi
    
    local temp_dir
    temp_dir=$(mktemp -d)
    cleanup_temp_dir() {
        if [[ -n "$temp_dir" ]] && [[ -d "$temp_dir" ]]; then
            rm -rf "$temp_dir"
        fi
    }
    
    # Распаковываем во временную папку
    if ! tar xzf "$backup_file" -C "$temp_dir" 2>/dev/null; then
        red "✗ Failed to extract backup"
        cleanup_temp_dir
        return 1
    fi
    
    # Определяем целевую директорию
    local target_base=""
    if [[ -d "/var/lib/caddy/.local/share" ]]; then
        target_base="/var/lib/caddy/.local/share"
    elif [[ -d "/root/.local/share" ]]; then
        target_base="/root/.local/share"
    else
        target_base="/var/lib/caddy/.local/share"
        mkdir -p "$target_base"
    fi
    
    green "✓ Target directory: $target_base"
    
    # Ищем распакованную папку caddy
    local source_caddy_dir=""
    source_caddy_dir=$(find "$temp_dir" -type d -name "caddy" 2>/dev/null | head -1)
    if [[ -z "$source_caddy_dir" ]]; then
        source_caddy_dir=$(find "$temp_dir" -type d -name "caddy-data" 2>/dev/null | head -1)
    fi
    
    if [[ -n "$source_caddy_dir" ]] && [[ -d "$source_caddy_dir" ]]; then
        systemctl stop caddy 2>/dev/null
        rm -rf "$target_base/caddy"
        if cp -r "$source_caddy_dir" "$target_base/caddy"; then
            green "✓ Caddy data restored from backup to: $target_base/caddy"
            
            local restored_cert
            restored_cert=$(find "$target_base/caddy" -name "*.crt" 2>/dev/null | head -1)
            if [[ -n "$restored_cert" ]]; then
                green "✓ Certificate file found: $(basename "$restored_cert")"
                local restored_domain
                restored_domain=$(openssl x509 -subject -noout -in "$restored_cert" 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')
                if [[ -n "$restored_domain" ]]; then
                    green "✓ Certificate domain: $restored_domain"
                    if [[ -z "$domain" ]] || [[ "$domain" != "$restored_domain" ]]; then
                        domain="$restored_domain"
                        save_runtime_config
                    fi
                fi
            fi
            
            systemctl start caddy 2>/dev/null
            sleep 3
            cleanup_temp_dir
            return 0
        else
            red "✗ Failed to copy restored data"
            systemctl start caddy 2>/dev/null
            cleanup_temp_dir
            return 1
        fi
    else
        # Пробуем старый формат (прямо certificates)
        local cert_dir
        cert_dir=$(find "$temp_dir" -type d -name "certificates" 2>/dev/null | head -1)
        if [[ -n "$cert_dir" ]]; then
            systemctl stop caddy 2>/dev/null
            mkdir -p "$target_base/caddy"
            if cp -r "$cert_dir" "$target_base/caddy/certificates"; then
                green "✓ Certificates restored from backup (legacy format)"
                systemctl start caddy 2>/dev/null
                sleep 3
                cleanup_temp_dir
                return 0
            fi
            systemctl start caddy 2>/dev/null
        fi
    fi
    
    red "✗ Failed to restore: no valid Caddy data found in backup"
    yellow "  Backup contents:"
    tar tzf "$backup_file" 2>/dev/null | head -5 | sed 's/^/    /'
    cleanup_temp_dir
    return 1
}

# =====================================
# Function: Check certificate status and backup info
# =====================================
check_certificate_status() {
    show_header
    
    if ! is_naive_installed; then
        yellow "  NaiveProxy is not installed!"
        show_footer
        return 0
    fi
    
    load_runtime_config
    
    if [[ -z "$domain" ]]; then
        red "✗ Domain not configured"
        show_footer
        return 1
    fi
    
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    green "                   Certificate Status"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo ""
    
    local cert_file
    cert_file=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    
    if [[ -n "$cert_file" ]] && [[ -f "$cert_file" ]]; then
        local expiry_date
        expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        local issuer
        issuer=$(openssl x509 -issuer -noout -in "$cert_file" 2>/dev/null | sed 's/issuer=//')
        
        local expiry_epoch
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
        local now_epoch
        now_epoch=$(date +%s)
        local days_left
        days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
        
        green "✓ Certificate found"
        echo -e "  ${GREEN}Domain:${PLAIN}     $domain"
        echo -e "  ${GREEN}Issuer:${PLAIN}     $issuer"
        echo -e "  ${GREEN}Expires:${PLAIN}    $expiry_date"
        
        # Определяем CA по issuer (более точно)
        if [[ "$issuer" =~ "ZeroSSL" ]]; then
            echo -e "  ${GREEN}CA:${PLAIN}         ZeroSSL (50 certs/week)"
        elif [[ "$issuer" =~ "Let's Encrypt" ]]; then
            echo -e "  ${GREEN}CA:${PLAIN}         Let's Encrypt (5 certs/week)"
        fi
        
        if [[ $days_left -lt 0 ]]; then
            red "  Status: EXPIRED"
        elif [[ $days_left -lt 7 ]]; then
            yellow "  Status:    Expires in $days_left days"
        else
            echo -e "  ${GREEN}Status:${PLAIN}     Valid ($days_left days remaining)"
        fi
    else
        # Сертификат не найден – анализируем логи Caddy
        red "✗ SSL certificate NOT FOUND"
        echo -e "  ${YELLOW}Last attempt details from Caddy log:${PLAIN}"
        
        # Ищем последнюю ошибку получения сертификата
        local last_error
        last_error=$(journalctl -u caddy --since "1 hour ago" --no-pager 2>/dev/null | grep -i "could not get certificate\|failed to obtain certificate" | tail -1)
        if [[ -n "$last_error" ]]; then
            # Извлекаем описание ошибки
            local error_desc
            error_desc=$(echo "$last_error" | sed -n 's/.*"error":\s*"\([^"]*\)".*/\1/p' | tail -1)
            [[ -n "$error_desc" ]] && echo -e "  ${RED}Error:${PLAIN} $error_desc"
            
            # Извлекаем retry after (время снятия лимита)
            local retry_after
            retry_after=$(echo "$last_error" | sed -n 's/.*retry after \([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\).*/\1/p')
            if [[ -n "$retry_after" ]]; then
                yellow "  ○ Let's Encrypt rate limit resets at: $retry_after UTC"
                yellow "  ○ Certificate will be obtained automatically after that time"
                yellow "  ○ You can also restart Caddy then (menu option 6)"
            fi
        else
            yellow "  (No recent errors – Caddy may still be working on it)"
        fi
    fi
    
    echo ""
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    green "                   Let's Encrypt Limits"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo ""
    
    # Проверяем логи Caddy за последние 7 дней
    local rate_limit_count
    rate_limit_count=$(journalctl -u caddy --since "7 days ago" 2>/dev/null | grep -ci "too many certificates")
    local cert_errors
    cert_errors=$(journalctl -u caddy --since "7 days ago" 2>/dev/null | grep -ci "failed to obtain certificate")
    local remaining
    remaining=$((5 - rate_limit_count))
    
    echo -e "${GREEN}  Certificates issued (last 7 days):${PLAIN} $rate_limit_count/5"
    
    if [[ $rate_limit_count -ge 5 ]]; then
        red "✗ RATE LIMIT EXCEEDED!"
        # Вытаскиваем время снятия лимита из логов
        local retry_after_line
        retry_after_line=$(journalctl -u caddy --since "7 days ago" --no-pager 2>/dev/null | sed -n 's/.*retry after \([0-9-]\{10\} [0-9:]\{8\}\).*/\1/p' | tail -1 | sed 's/retry after //')
        if [[ -n "$retry_after_line" ]]; then
            yellow "○ Rate limit reset at: $retry_after_line UTC"
        else
            yellow "○ No new certificates until next week"
        fi
        yellow "○ Use 'Restore' instead"
    elif [[ $rate_limit_count -ge 4 ]]; then
        yellow "○ WARNING: Only $remaining certificate(s) left this week"
    else
        green "✓ $remaining certificate(s) remaining this week"
    fi
    
    if [[ $cert_errors -gt 0 ]]; then
        yellow "○ Certificate failures (last 7 days): $cert_errors"
    fi
    
    echo ""
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    green "                       Backup Info"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo ""
    
    local backup_dir="/root/naive/cert-backup"
    local backup_file=""
    local domain_from_backup=""
    local caddy_version_short=""
    
    if [[ -f "$backup_dir/caddy_data_${domain}.tar.gz" ]]; then
        backup_file="$backup_dir/caddy_data_${domain}.tar.gz"
    elif [[ -f "$backup_dir/certs_${domain}.tar.gz" ]]; then
        backup_file="$backup_dir/certs_${domain}.tar.gz"
    fi
    
    # Извлекаем domain и короткую версию Caddy из metadata.txt
    if [[ -f "$backup_dir/metadata.txt" ]]; then
        domain_from_backup=$(grep "^Domain:" "$backup_dir/metadata.txt" 2>/dev/null | cut -d: -f2- | xargs)
        local full_version
        full_version=$(grep "^Caddy version:" "$backup_dir/metadata.txt" 2>/dev/null | cut -d: -f2- | xargs)
        # Оставляем только первую часть до пробела (v2.11.3)
        caddy_version_short=$(echo "$full_version" | awk '{print $1}')
    fi
    
    if [[ -n "$backup_file" ]] && [[ -f "$backup_file" ]]; then
        green "✓ Backup exists"
        echo -e "  ${GREEN}File:${PLAIN}             $(basename "$backup_file")"
        echo -e "  ${GREEN}Size:${PLAIN}             $(du -h "$backup_file" | awk '{print $1}')"
        
        [[ -n "$domain_from_backup" ]] && echo -e "  ${GREEN}Domain in backup:${PLAIN} $domain_from_backup"
        [[ -n "$caddy_version_short" ]] && echo -e "  ${GREEN}Caddy version:${PLAIN}    $caddy_version_short"
        
        if [[ -f "$backup_dir/metadata.txt" ]]; then
            local backup_date
            backup_date=$(grep "Backup date:" "$backup_dir/metadata.txt" 2>/dev/null | cut -d: -f2- | xargs)
            local backup_path
            backup_path=$(grep "Backup path:" "$backup_dir/metadata.txt" 2>/dev/null | cut -d: -f2- | xargs)
            
            [[ -n "$backup_date" ]] && echo -e "  ${GREEN}Backup date:${PLAIN}      $backup_date"
            [[ -n "$backup_path" ]] && echo -e "  ${GREEN}Source path:${PLAIN}      $backup_path"
        fi
    else
        yellow "○ No backup found"
        echo -e "  ${YELLOW}Tip:${PLAIN} Run option ${GREEN}13${PLAIN} to create a backup"
    fi
    
    # Список всех бэкапов и их содержимого (без повтора metadata)
    if [[ ! -d "$backup_dir" ]]; then
        yellow "○ No backup directory found"
    else
        echo -e "  ${GREEN}Backup directory:${PLAIN} $backup_dir"
        echo ""
        
        # Перебираем файлы архивов
        for backup in "$backup_dir"/*.tar.gz; do
            [[ -f "$backup" ]] || continue
            echo ""
            echo -e "  ${GREEN}Contents of${PLAIN} ${YELLOW}$(basename "$backup"):${PLAIN}"
            tar tzf "$backup" 2>/dev/null | head -10 | sed 's/^/  /'
            local total
            total=$(tar tzf "$backup" 2>/dev/null | wc -l)
            if [[ $total -gt 10 ]]; then
                echo "  ... and $((total - 10)) more files"
            fi
        done
    fi
    
    echo ""
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
	
    show_footer
}

# =====================================
# Function: Draw header (без clear для вложенных вызовов)
# =====================================
draw_header() {
    yellow "###############################################################"
    echo -e "  ${YELLOW}NaiveProxy Manager${PLAIN}                                   ${BLUE}Kordan${PLAIN}  "
    yellow "###############################################################"
    echo ""
}

# =====================================
# Function: Clear screen and draw header
# =====================================
show_header() {
    clear
    draw_header
}

# =====================================
# Function: Show footer
# =====================================
show_footer() {
    echo ""
    yellow "###############################################################"
}

# =====================================
# Function: Check if certificate is valid and working
# =====================================
check_certificate_valid() {
    local domain=$1
    
    # Реальная проверка через подключение
	if timeout 5 bash -c "echo | openssl s_client -connect '${domain}:443' -servername '$domain' 2>/dev/null" | openssl x509 -noout -dates 2>/dev/null | grep -q "notAfter="; then	
        return 0
    fi
    
    # Fallback: проверяем только файл
    local cert_file
    cert_file=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    if [[ -z "$cert_file" ]] || [[ ! -f "$cert_file" ]]; then
        return 1
    fi
    
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    local now_epoch
    now_epoch=$(date +%s)
    
    if [[ $expiry_epoch -le $now_epoch ]]; then
        return 1
    fi
    
    # Файл есть и не истек, но проверяем, слушает ли порт
    if ! timeout 3 bash -c "echo >/dev/tcp/$domain/443" 2>/dev/null; then
        return 1
    fi
    
    return 0
}

# =====================================
# Function: Check if certificate is actually working
# =====================================
check_certificate_working() {
    local domain=$1
    
    # Проверка 1: Пытаемся получить сертификат через openssl s_client (реальное подключение)
    cert_info=$(timeout 5 openssl s_client -connect "${domain}:443" -servername "$domain" < /dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    
    if [[ -n "$cert_info" ]]; then
        # Сертификат работает и доступен через сеть
        local expiry_date
        expiry_date=$(echo "$cert_info" | grep "notAfter=" | cut -d= -f2)
        if [[ -n "$expiry_date" ]]; then
            echo "WORKING:$expiry_date"
            return 0
        fi
    fi
    
    # Проверка 2: Проверяем доступность порта 443
    if timeout 3 bash -c "echo >/dev/tcp/$domain/443" 2>/dev/null; then
        # Порт открыт, но сертификат не получен (возможно, самоподписанный или проблемы)
        echo "PORT_OPEN_NO_CERT"
        return 5
    fi
    
    # Проверка 3: Ищем файл сертификата на диске
    local cert_file
    cert_file=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    
    if [[ -n "$cert_file" ]] && [[ -f "$cert_file" ]]; then
        # Проверяем, соответствует ли сертификат домену
        local cert_domain
        cert_domain=$(openssl x509 -subject -noout -in "$cert_file" 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')
        if [[ -n "$cert_domain" ]] && [[ "$cert_domain" != "$domain" ]]; then
            echo "WRONG_DOMAIN:$cert_domain"
            return 2
        fi
        
        # Проверяем срок действия
        local expiry_date
        expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        local expiry_epoch
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
        local now_epoch
        now_epoch=$(date +%s)
        
        if [[ $expiry_epoch -le $now_epoch ]]; then
            echo "EXPIRED:$expiry_date"
            return 3
        else
            # Файл есть и не истек, но Caddy его не использует (порт не слушает)
            echo "FILE_ONLY:$expiry_date"
            return 4
        fi
    fi
    
    echo "MISSING"
    return 1
}

# =====================================
# Function: Restart SSH service (supports both sshd and ssh)
# Description: Detects correct service name and restarts SSH
# =====================================
restart_ssh() {
    if systemctl list-units 2>/dev/null | grep -q "sshd.service"; then
        systemctl restart sshd
    else
        systemctl restart ssh
    fi
}

# =====================================
# Function: Check and update NaiveProxy/Caddy (improved)
# =====================================
check_and_update_naive() {
    show_header
    
    # Проверяем, установлен ли NaiveProxy (полноценно, с конфигом и сервисом)
    if ! is_naive_installed; then
        yellow "  NaiveProxy is NOT installed"
        
        # Проверяем, не остались ли рудименты Caddy (бинарник или сервис)
        if command -v caddy &>/dev/null || systemctl list-unit-files 2>/dev/null | grep -q "^caddy.service"; then
            echo ""
            yellow "  However, leftover Caddy files were found:"
            command -v caddy &>/dev/null && echo "  - Binary: $(which caddy)"
            systemctl list-unit-files 2>/dev/null | grep -q "^caddy.service" && echo "  - Systemd service: caddy.service"
            echo ""
            read -rp "Remove these leftovers? [y/N]: " remove_leftovers
            if [[ "$remove_leftovers" =~ ^[Yy]$ ]]; then
                systemctl stop caddy 2>/dev/null
                systemctl disable caddy 2>/dev/null
                rm -f /usr/bin/caddy
                rm -f /etc/systemd/system/caddy.service
                systemctl daemon-reload
                green "✓ Leftover Caddy files removed"
            fi
        else
            echo ""
            green "  No NaiveProxy installation detected. Nothing to update"
        fi
        show_footer
        return 0
    fi
    
    load_runtime_config
    
    local current_version
    current_version=$(caddy version 2>/dev/null | awk '{print $1}')
    local latest_go_version
    latest_go_version=$(curl -s --max-time 10 https://go.dev/VERSION?m=text | head -n 1)
    
    echo -e "${GREEN}Current Caddy version:${PLAIN} ${current_version:-not installed}"
    local latest_go_display="${latest_go_version#go}"
    echo -e "${GREEN}Latest Go version:${PLAIN} ${latest_go_display:-unknown}"
    echo ""
    
    # Проверка наличия forwardproxy плагина
    if caddy list-modules 2>/dev/null | grep -qi "forward_proxy"; then
        green "✓ NaiveProxy forwardproxy plugin is present"
    else
        red "✗ Forwardproxy plugin MISSING! Rebuild required"
    fi
    
    read -rp "Recompile Caddy with latest forwardproxy? [y/N]: " confirm
	if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
		green "  Skipping NaiveProxy update"
		show_footer
		return 0
	fi
    
    # Останавливаем Caddy, если он запущен
    if systemctl is-active --quiet caddy 2>/dev/null; then
        systemctl stop caddy
    fi
    
    # --- Резервная копия текущего бинарника ---
    if [[ -f /usr/bin/caddy ]]; then
        cp /usr/bin/caddy /usr/bin/caddy.bak
        green "✓ Backup of current Caddy saved to /usr/bin/caddy.bak"
    fi
    
    # Переустанавливаем Go и пересобираем Caddy
    install_go
    if ! build_caddy; then
        red "✗ Caddy rebuild failed!"
        # Восстанавливаем старый бинарник, если он был
        if [[ -f /usr/bin/caddy.bak ]]; then
            mv /usr/bin/caddy.bak /usr/bin/caddy
            green "✓ Restored previous Caddy binary"
        else
            # Если бэкапа не было (впервые устанавливаем), просто пытаемся запустить то, что есть
            :
        fi
        systemctl start caddy 2>/dev/null
        show_footer
        return 1
    fi
    
    # Если сборка успешна, удаляем бэкап
    rm -f /usr/bin/caddy.bak
    
    # Проверяем наличие Caddyfile – если нет, пересоздаём
    if [[ ! -f /etc/caddy/Caddyfile ]]; then
        yellow "○ Caddyfile not found, recreating configuration ..."
        create_configs
    fi
    
    # Проверяем наличие systemd-сервиса – если нет, создаём
    if systemctl list-unit-files 2>/dev/null | grep -q "^caddy.service"; then
        systemctl start caddy
        green "✓ NaiveProxy refreshed to latest forwardproxy version"
    else
        create_systemd_service
        green "✓ Caddy rebuilt and service recreated"
    fi
    
    # Финальная проверка, что Caddy запустился
    sleep 3
    if systemctl is-active --quiet caddy; then
        green "✓ Caddy service is running after update"
    else
        red "✗ Caddy service failed to start after update. Check logs: journalctl -u caddy -n 30"
        journalctl -u caddy -n 30 --no-pager
        return 1
    fi
    
    show_footer
}

# =====================================
# Function: Setup systemd timer for Caddy auto-update (weekly)
# Replaces old cron-based approach
# =====================================
setup_systemd_updates() {
    yellow "  Setting up systemd timer for Caddy auto-update (weekly) ..."

    # Создаём скрипт обновления (сохраняем существующую логику)
    cat > /usr/local/bin/naive-update << 'EOF'
#!/bin/bash
LOG="/var/log/naive-update.log"
echo "[$(date)] Checking NaiveProxy update ..." >> "$LOG"

if [[ ! -f /usr/bin/caddy ]]; then
    echo "[$(date)] Caddy not found, skipping" >> "$LOG"
    exit 0
fi

LAST_BUILD=$(stat -c %Y /usr/bin/caddy 2>/dev/null)
NOW=$(date +%s)
DAYS=$(( (NOW - LAST_BUILD) / 86400 ))

if [[ $DAYS -lt 30 ]]; then
    echo "[$(date)] Last build $DAYS days ago, skipping" >> "$LOG"
    exit 0
fi

echo "[$(date)] Rebuilding Caddy (last build: $DAYS days ago)" >> "$LOG"

systemctl stop caddy

export PATH=$PATH:/usr/local/go/bin
cd /root || { echo "[$(date)] Cannot cd to /root" >> "$LOG"; exit 1; }
rm -rf /root/tmp
mkdir -p /root/tmp
export TMPDIR=/root/tmp

export GOBIN=/root/go/bin
export PATH=$PATH:/usr/local/go/bin:$GOBIN
if ! command -v xcaddy &>/dev/null; then
    echo "[$(date)] xcaddy not found, attempting to install..." >> "$LOG"
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
fi

xcaddy build \
    --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/rushiiMachine/caddy-ja3 \
    --with github.com/rushiiMachine/caddy-deflate \
    --with github.com/ueffel/caddy-brotli \
    --with github.com/mholt/caddy-l4 \
    >> "$LOG" 2>&1

if [[ -f ./caddy ]]; then
    mv ./caddy /usr/bin/caddy
    
    # Проверяем наличие forwardproxy (только вывод в лог, без цветов)
    if caddy list-modules 2>/dev/null | grep -qi forwardproxy; then
        echo "[$(date)] Forwardproxy plugin present in new build" >> "$LOG"
    else
        echo "[$(date)] WARNING: Forwardproxy plugin MISSING! Build may be broken" >> "$LOG"
    fi
    
    chmod +x /usr/bin/caddy
    systemctl start caddy
    echo "[$(date)] Caddy rebuilt successfully" >> "$LOG"
else
    echo "[$(date)] Build failed!" >> "$LOG"
    systemctl start caddy
fi
EOF

    chmod +x /usr/local/bin/naive-update

    # systemd сервис для обновления Caddy
    cat > /etc/systemd/system/caddy-update.service << EOF
[Unit]
Description=Rebuild Caddy with latest forwardproxy
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/naive-update
StandardOutput=journal
StandardError=journal
User=root
EOF

    # systemd таймер – еженедельно в воскресенье в 3:00 ночи
    cat > /etc/systemd/system/caddy-update.timer << EOF
[Unit]
Description=Weekly rebuild of Caddy (Sunday 3:00 AM)
Requires=caddy-update.service

[Timer]
OnCalendar=Sun *-*-* 03:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now caddy-update.timer	
    green "✓ Caddy auto-update systemd timer installed (weekly, Sunday 3:00 AM)"

    # Настраиваем ротацию логов
    cat > /etc/logrotate.d/naive-update << EOF
/var/log/naive-update.log {
    monthly
    rotate 12
    compress
    missingok
    notifempty
    create 644 root root
}
EOF
    green "✓ Log rotation configured for naive-update (monthly, keep 12 months)"

    # Удаляем старые cron-задачи, если они ещё есть (чистка при обновлении)
    if crontab -l 2>/dev/null | grep -q "naive-update\|caddy-update"; then
        crontab -l 2>/dev/null | grep -v "naive-update\|caddy-update" | crontab -
        yellow "○ Removed old cron jobs for naive/caddy updates"
    fi
}

# =====================================
# Function: Show system information
# =====================================
show_system_info() {
    show_header
	
	# Убедимся, что SYSTEM определена
	if [[ -z "$SYSTEM" ]] && SYSTEM="Unknown"; then
		detect_os_light
	fi
	
	echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    green "                     System Information"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    
    echo -e "${GREEN}  Operating System:${PLAIN}   $SYSTEM $VERSION"
    echo -e "${GREEN}  Architecture:${PLAIN}       $(uname -m)"
    echo -e "${GREEN}  Kernel:${PLAIN}      $(uname -r)"
    echo -e "${GREEN}  Uptime:${PLAIN}      $(uptime -p | sed 's/up //')"
    echo -e "${GREEN}  CPU:${PLAIN}         $(nproc) cores"
    
    TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
    USED_RAM=$(free -h | awk '/^Mem:/ {print $3}')
    FREE_RAM=$(free -h | awk '/^Mem:/ {print $4}')
    RAM_PERCENT=$(free | awk '/^Mem:/ {printf "%.1f%%", $3/$2 * 100.0}')
    echo -e "${GREEN}  RAM:${PLAIN}         Total: $TOTAL_RAM, Used: $USED_RAM, Free: $FREE_RAM ($RAM_PERCENT)"
    
	if swapon --show 2>/dev/null | grep -q "/swapfile"; then
		SWAP_SIZE_KB=$(swapon --show --bytes 2>/dev/null | awk '/swapfile/ {print $3}')
		if [[ -n "$SWAP_SIZE_KB" ]]; then
			SWAP_SIZE_MB=$((SWAP_SIZE_KB / 1024))
			SWAP_SIZE_GB=$((SWAP_SIZE_MB / 1024))
			if [[ $SWAP_SIZE_GB -gt 0 ]]; then
				SWAP_SIZE="${SWAP_SIZE_GB} GB"
			else
				SWAP_SIZE="${SWAP_SIZE_MB} MB"
			fi
		else
			SWAP_SIZE="unknown"
		fi
		echo -e "${GREEN}  Swap:${PLAIN}        $SWAP_SIZE (active)"
	else
		echo -e "${GREEN}  Swap:${PLAIN}        not configured"
	fi
    
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    DISK_PERCENT=$(df / | awk 'NR==2 {print $5}')
    echo -e "${GREEN}  Disk (/):${PLAIN}    Total: $DISK_TOTAL, Used: $DISK_USED, Free: $DISK_FREE ($DISK_PERCENT)"
    
    SERVER_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "unknown")
    echo -e "${GREEN}  External IP:${PLAIN} $SERVER_IP"
    
    CONNS=$(ss -t state established | wc -l)
    echo -e "${GREEN}  Active connections:${PLAIN} $CONNS"
    
    case $SYSTEM in
        "Debian"|"Ubuntu")
            if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
                echo -e "${GREEN}  Firewall:${PLAIN}           UFW (active)"
            else
                echo -e "${GREEN}  Firewall:${PLAIN}           not active"
            fi
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            if systemctl is-active --quiet firewalld 2>/dev/null; then
                echo -e "${GREEN}  Firewall:${PLAIN}           firewalld (active)"
            else
                echo -e "${GREEN}  Firewall:${PLAIN}           not active"
            fi
            ;;
        *)
            echo -e "${GREEN}  Firewall:${PLAIN}                unknown"
            ;;
    esac
    
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        echo -e "${GREEN}  TCP congestion:${PLAIN}     BBR"
    else
        echo -e "${GREEN}  TCP congestion:${PLAIN} $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'unknown')"
    fi
    
    echo -e "${GREEN}  Bash:${PLAIN}               ${BASH_VERSION}"
   
    if command -v openssl &>/dev/null; then
        SSL_VERSION=$(openssl version | awk '{print $1, $2}')
        echo -e "${GREEN}  OpenSSL:${PLAIN}            $SSL_VERSION"
    fi
    
    echo ""
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    green "                      NaiveProxy Status"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    
    if ! is_naive_installed; then
        echo ""
        red "✗ NaiveProxy is NOT installed"
        show_footer
        return 0
    fi
    
    if [[ -f /root/naive/runtime.env ]]; then
		# shellcheck source=/dev/null
        source /root/naive/runtime.env
        green "✓ Configuration:   loaded"
        
        # +++ Добавляем проверку валидности полей конфигурации (взято из validate_configuration)
        local config_valid=true
        if [[ -z "$domain" ]]; then
            red "✗ Configuration: domain is missing"
            config_valid=false
        elif ! echo "$domain" | grep -qE '^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$'; then
            red "✗ Configuration: invalid domain format ($domain)"
            config_valid=false
        fi
        
        if [[ -z "$proxyport" ]]; then
            red "✗ Configuration: proxy port is missing"
            config_valid=false
        elif [[ ! "$proxyport" =~ ^[0-9]+$ ]]; then
            red "✗ Configuration: proxy port is not a number ($proxyport)"
            config_valid=false
        fi
        
        if [[ -z "$email" ]]; then
            red "✗ Configuration: email is missing"
            config_valid=false
        elif ! echo "$email" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
            red "✗ Configuration: invalid email format ($email)"
            config_valid=false
        fi
        
        if [[ "$config_valid" == true ]]; then
            green "✓ Configuration:   all fields valid"
        fi
        # +++ Конец добавления
    else
        red "✗ Configuration file not found"
        show_footer
        return 1
    fi
    
	if [[ -z "$domain" ]]; then
		red "✗ Domain: missing"
	else
		green "✓ Domain:          $domain"
	fi
	if [[ -z "$proxyport" ]]; then
		red "✗ Proxy port: missing"
	else
		green "✓ Proxy port:      $proxyport"
	fi
	if [[ -z "$proxyname" ]]; then
		red "✗ Username: missing"
	else
		green "✓ Username:        $proxyname"
	fi
	if [[ -z "$proxypwd" ]]; then
		red "✗ Password: missing"
	else
		green "✓ Password:        [set]"
	fi
    
    # РЕАЛЬНАЯ ПРОВЕРКА СЕРТИФИКАТА
    local cert_status
    cert_status=$(check_certificate_working "$domain")
    
    case $cert_status in
        WORKING:*)
            local expiry_date="${cert_status#WORKING:}"
            green "✓ SSL certificate: WORKING and accessible"
            echo -e "  ${GREEN}Expires:${PLAIN}         $expiry_date"
            ;;
        WRONG_DOMAIN:*)
            local wrong_domain="${cert_status#WRONG_DOMAIN:}"
            red "✗ SSL certificate: WRONG DOMAIN"
            echo -e "  ${RED}Expected:${PLAIN} $domain"
            echo -e "  ${RED}Found:${PLAIN} $wrong_domain"
            ;;
        EXPIRED:*)
            local expiry_date="${cert_status#EXPIRED:}"
            red "✗ SSL certificate: EXPIRED"
            echo -e "  ${RED}Expired on:${PLAIN} $expiry_date"
            ;;
        FILE_ONLY:*)
            local expiry_date="${cert_status#FILE_ONLY:}"
            yellow "○ SSL certificate: FILE EXISTS BUT Caddy IS NOT RESPONDING"
            yellow "  ○ Certificate file found on disk but port 443 is not accessible"
            yellow "  ○ Check if Caddy is running: systemctl status caddy"
            echo -e "  ${YELLOW}Expires:${PLAIN} $expiry_date"
            ;;
        PORT_OPEN_NO_CERT)
            red "✗ Port 443 is open but no valid certificate found"
            yellow "  ○ Check Caddy logs: journalctl -u caddy -n 50"
            ;;
        MISSING)
            red "✗ SSL certificate: NOT FOUND"
            yellow "  ○ No certificate file for domain $domain"
            ;;
        *)
            red "✗ SSL certificate: UNKNOWN STATUS"
            ;;
    esac
    
    if command -v caddy &>/dev/null; then
        CADDY_VER=$(caddy version 2>/dev/null | awk '{print $1}')
        echo -e "${GREEN}  Caddy version:${PLAIN}   $CADDY_VER"
    fi
    
    if command -v go &>/dev/null; then
        GO_VER=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//')
        echo -e "${GREEN}  Go version:${PLAIN}      $GO_VER"
    fi

    if systemctl is-active --quiet caddy 2>/dev/null; then
        green "✓ Caddy service:   running"
    else
        red "✗ Caddy service:   NOT running"
    fi
    
    if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban 2>/dev/null; then
        JAILED=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print $4}' || echo "0")
        green "✓ fail2ban:        running (banned: $JAILED IPs)"
    else
        yellow "○ fail2ban:        not running"
    fi
    
	if [[ "$SERVER_IP" != "unknown" ]]; then
        if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/443" 2>/dev/null; then
            green "✓ Port 443:        reachable from internet"
        else
            red "✗ Port 443:          NOT reachable from internet"
            yellow "○ Check firewall and NAT settings"
        fi
    else
        yellow "○ Could not determine external IP"
    fi
	
	echo -e "${YELLOW}  Public ports (accessible from internet):${PLAIN}"
	PUBLIC_PORTS=$(ss -tlnp 2>/dev/null | grep -v "127.0.0.1" | grep -v "::1" | awk '{print $4}' | grep -oE ':[0-9]+$' | sort -u | sed 's/://' | tr '\n' ' ')
	if [[ -n "$PUBLIC_PORTS" ]]; then
		echo "  ${PUBLIC_PORTS}"
	else
		echo "  none"
	fi
    
    show_footer
}

# =====================================
# Function: Update package lists
# =====================================
update_package_lists() {
    case $SYSTEM in
        "Debian"|"Ubuntu")
            for i in 1 2 3; do
                if apt-get update -qq; then
                    green "✓ Package lists updated"
                    return 0
                fi
                sleep 4
            done
            red "✗ Failed to update package lists after 3 attempts"
            exit 1
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            dnf makecache -q 2>/dev/null || true
            dnf check-update -q || true
            green "✓ Package lists refreshed"
            ;;
    esac
}

# =====================================
# Function: Upgrade all packages
# =====================================
upgrade_all_packages() {
    case $SYSTEM in
        "Debian"|"Ubuntu")
            read -rp "Upgrade all packages? [Y/n]: " confirm
            if [[ "$confirm" =~ ^[Nn]$ ]]; then
                yellow "○ Upgrade cancelled"
            else
                apt-get full-upgrade -y
                green "✓ Packages upgraded"
            fi
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            read -rp "Update all packages? [Y/n]: " confirm
            if [[ "$confirm" =~ ^[Nn]$ ]]; then
                yellow "○ Update cancelled"
            else
                dnf update -y
                green "✓ Packages updated"
            fi
            ;;
    esac
}

# =====================================
# Function: Clean up unused packages
# =====================================
cleanup_unused_packages() {
    case $SYSTEM in
        "Debian"|"Ubuntu")
            read -rp "Remove unused packages? [Y/n]: " confirm
            if [[ "$confirm" =~ ^[Nn]$ ]]; then
                yellow "○ Cleanup cancelled"
            else
                apt-get autoremove -y
                apt-get autoclean -y
                green "✓ Cleanup completed"
            fi
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            read -rp "Clean DNF cache? [Y/n]: " confirm
            if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                dnf clean all
                green "✓ Cache cleaned"
            fi
            
            echo ""
            read -rp "Remove old kernels (keep 2 most recent)? [Y/n]: " confirm_kernel
            if [[ ! "$confirm_kernel" =~ ^[Nn]$ ]]; then
                package-cleanup --oldkernels --count=2 -y 2>/dev/null || true
                green "✓ Old kernels cleaned"
            fi
            
            echo ""
            read -rp "Remove unused packages? [Y/n]: " confirm_autoremove
            if [[ ! "$confirm_autoremove" =~ ^[Nn]$ ]]; then
                dnf autoremove -y
                green "✓ Unused packages removed"
            fi
            ;;
    esac
}

# =====================================
# Function: System maintenance
# =====================================
system_maintenance() {
    show_header
    
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}              System Maintenance Options${PLAIN}"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo ""
    echo -e " ${GREEN}1.${PLAIN}  Update package lists"
    echo -e " ${GREEN}2.${PLAIN}  Upgrade all packages"
    echo -e " ${GREEN}3.${PLAIN}  Clean up unused packages"
    echo -e " ${GREEN}4.${PLAIN}  Full maintenance (all of the above)"
    echo ""
    echo -e " ${RED}0.${PLAIN}  Cancel"
    echo ""
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo ""
    
    local maint_choice
    read -rp " Your choice [0-4]: " maint_choice
    echo ""
    
    case $maint_choice in
        0)
            green "✓ Maintenance cancelled"
            show_footer
            return 0
            ;;
        1)
            update_package_lists
            ;;
        2)
            upgrade_all_packages
            ;;
        3)
            cleanup_unused_packages
            ;;
        4)
            yellow "→ Running full maintenance ..."
            echo ""
            update_package_lists
            upgrade_all_packages
            cleanup_unused_packages
            ;;
        *)
            red "✗ Invalid choice"
            show_footer
            return 1
            ;;
    esac
    
    green "✓ System maintenance completed!"
    show_footer
}

# =====================================
# Function: Setup NaiveGuard pro-active watchdog (silent, self-healing only)
# =====================================
setup_naiveguard() {
    yellow "  Setting up NaiveGuard pro-active watchdog for self-healing ..."

    cat > /usr/local/bin/naiveguard.sh << 'SCRIPT_EOF'
#!/bin/bash
LOG="/var/log/naiveguard.log"
LOCKFILE="/var/lock/naiveguard.lock"

# Блокировка для предотвращения параллельного запуска
exec 200>"$LOCKFILE"
flock -n 200 || exit 0

# ===== Проверка 1: Работа Caddy =====
if ! systemctl is-active --quiet caddy; then
    echo "[$(date)] Caddy is down, restarting ..." >> "$LOG"
    systemctl restart caddy
    sleep 5
    if ! systemctl is-active --quiet caddy; then
        echo "[$(date)] Caddy restart failed." >> "$LOG"
    fi
fi

# ===== Проверка 2: Срок годности бинарника Caddy =====
if [[ -f /usr/bin/caddy ]]; then
    LAST_BUILD=$(stat -c %Y /usr/bin/caddy)
    NOW=$(date +%s)
    DAYS_SINCE_BUILD=$(( (NOW - LAST_BUILD) / 86400 ))
    if [[ $DAYS_SINCE_BUILD -gt 30 ]]; then
        echo "[$(date)] Caddy binary is $DAYS_SINCE_BUILD days old. Auto-rebuilding ..." >> "$LOG"
        if command -v xcaddy &>/dev/null && command -v go &>/dev/null; then
            systemctl stop caddy
            export GOBIN=/root/go/bin
            export PATH=$PATH:/usr/local/go/bin:$GOBIN
            mkdir -p /root/tmp && export TMPDIR=/root/tmp
			
            xcaddy build \
				--with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive \
				--with github.com/mholt/caddy-ratelimit \
				--with github.com/rushiiMachine/caddy-ja3 \
				--with github.com/rushiiMachine/caddy-deflate \
				--with github.com/ueffel/caddy-brotli \
				--with github.com/mholt/caddy-l4
                
            if [[ -f ./caddy ]]; then
                mv -f ./caddy /usr/bin/caddy
                chmod +x /usr/bin/caddy
                systemctl start caddy
                echo "[$(date)] Auto-rebuild SUCCESS" >> "$LOG"
            else
                systemctl start caddy
                echo "[$(date)] Auto-rebuild FAILED" >> "$LOG"
            fi
        else
            echo "[$(date)] xcaddy or go not found, cannot auto-rebuild" >> "$LOG"
        fi
    fi
fi

# ===== Проверка 3: Сертификат и лимиты =====
if [[ -f /root/naive/runtime.env ]]; then
    # Безопасно загружаем конфиг, игнорируя ошибки
    set -a
	# shellcheck source=/dev/null
    source /root/naive/runtime.env 2>/dev/null
    set +a
    if [[ -z "$domain" ]]; then
        echo "[$(date)] Domain not defined in runtime.env" >> "$LOG"
    else
        # Ищем сертификат (домены не содержат спецсимволов, экранирование не требуется)
        CERT_FILE=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -type f -name "${domain}.crt" 2>/dev/null | head -1)
        
        if [[ -z "$CERT_FILE" ]]; then
            echo "[$(date)] Certificate not found for domain $domain. Attempting restore from backup ..." >> "$LOG"
            BACKUP_FILE=$(ls -t /root/naive/cert-backup/caddy_data_*.tar.gz 2>/dev/null | head -1)
            if [[ -n "$BACKUP_FILE" ]]; then
                tmp_dir=$(mktemp -d)
                # Удаляем временную директорию при любом выходе из этого блока
                trap 'rm -rf "$tmp_dir"' EXIT
                tar xzf "$BACKUP_FILE" -C "$tmp_dir" 2>/dev/null
                SRC=$(find "$tmp_dir" -type d -name "caddy" | head -1)
                if [[ -n "$SRC" ]]; then
                    # Определяем целевую директорию для Caddy
                    if [[ -d /var/lib/caddy/.local/share/caddy ]]; then
                        TARGET="/var/lib/caddy/.local/share"
                    elif [[ -d /root/.local/share/caddy ]]; then
                        TARGET="/root/.local/share"
                    else
                        TARGET="/root/.local/share"
                        mkdir -p "$TARGET"
                    fi
                    
                    CERT_IN_BACKUP=$(find "$SRC" -type f -name "${domain}.crt" 2>/dev/null | head -1)
                    if [[ -n "$CERT_IN_BACKUP" ]]; then
                        EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_IN_BACKUP" 2>/dev/null | cut -d= -f2)
                        if [[ -n "$EXPIRY" ]]; then
                            EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null)
                            if [[ $EXPIRY_EPOCH -gt $(date +%s) ]]; then
                                rm -rf "$TARGET/caddy"
                                cp -r "$SRC" "$TARGET/caddy"
                                systemctl restart caddy
                                sleep 3
                                if systemctl is-active --quiet caddy; then
                                    echo "[$(date)] Certificate restored from backup (valid until $EXPIRY)" >> "$LOG"
                                else
                                    echo "[$(date)] Certificate restored but Caddy failed to start" >> "$LOG"
                                fi
                            else
                                echo "[$(date)] Backup certificate expired on $EXPIRY, not restoring" >> "$LOG"
                            fi
                        fi
                    else
                        echo "[$(date)] No certificate found in backup" >> "$LOG"
                    fi
                fi
                # Снимаем trap и удаляем директорию
                trap - EXIT
                rm -rf "$tmp_dir"
            else
                # Разбор лимитов Let's Encrypt
                RETRY_LOG=$(journalctl -u caddy --since "1 hour ago" --no-pager 2>/dev/null | sed -n 's/.*retry after \([0-9-]\{10\} [0-9:]\{8\}\).*/\1/p' | sed 's/retry after //' | tail -1)
                if [[ -n "$RETRY_LOG" ]]; then
                    RETRY_EPOCH=$(date -d "$RETRY_LOG" +%s 2>/dev/null)
                    NOW_EPOCH=$(date +%s)
                    if [[ -n "$RETRY_EPOCH" && $NOW_EPOCH -gt $RETRY_EPOCH ]]; then
                        echo "[$(date)] Rate limit window passed, restarting Caddy to obtain certificate ..." >> "$LOG"
                        systemctl restart caddy
                    else
                        echo "[$(date)] Rate limit still active until $RETRY_LOG, waiting" >> "$LOG"
                    fi
                fi
            fi
        fi
    fi
fi

# ===== Проверка 4: Свободное место (безопасная очистка) =====
USED=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $USED -gt 90 ]]; then
    echo "[$(date)] Disk usage >90%, cleaning temp files and old Caddy build caches ..." >> "$LOG"
    rm -rf /root/tmp/*
    rm -rf /root/.cache/go-build
    journalctl --vacuum-size=100M 2>/dev/null
fi

# ===== Проверка 5: fail2ban =====
if command -v fail2ban-client &>/dev/null; then
    if ! systemctl is-active --quiet fail2ban; then
        echo "[$(date)] fail2ban not running, restarting ..." >> "$LOG"
        systemctl restart fail2ban
    fi
fi

echo "[$(date)] NaiveGuard check completed" >> "$LOG"
exit 0
SCRIPT_EOF

    chmod +x /usr/local/bin/naiveguard.sh

    cat > /etc/systemd/system/naiveguard.service << EOF
[Unit]
Description=NaiveGuard – pro-active self-healing watchdog
After=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/naiveguard.sh
StandardOutput=journal
StandardError=journal
EOF

    cat > /etc/systemd/system/naiveguard.timer << EOF
[Unit]
Description=Run NaiveGuard every 10 minutes
Requires=naiveguard.service

[Timer]
OnCalendar=*:0/10
RandomizedDelaySec=60
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now naiveguard.timer 2>/dev/null

    if systemctl is-enabled naiveguard.timer &>/dev/null; then
        green "✓ NaiveGuard timer enabled"
    else
        red "✗ Failed to enable NaiveGuard timer"
    fi

    # Создаём лог-файл и директорию для блокировок
    touch /var/log/naiveguard.log
    chmod 644 /var/log/naiveguard.log
    mkdir -p /var/lock

    cat > /etc/logrotate.d/naiveguard << EOF
/var/log/naiveguard.log {
    monthly
    rotate 3
    compress
    missingok
    notifempty
    create 644 root root
}
EOF

    green "✓ NaiveGuard pro-active watchdog installed (runs every 10 minutes)"
    echo "  Logs: tail -f /var/log/naiveguard.log"
}

# =====================================
# Function: Enable Oracle Epel
# =====================================
enable_oracle_epel() {
	local ol_version=""
	if [[ -f /etc/os-release ]]; then
		ol_version=$(grep -oE 'VERSION_ID="[0-9]+"' /etc/os-release | grep -oE '[0-9]+')
	fi
	if [[ -z "$ol_version" ]] && [[ -f /etc/oracle-release ]]; then
		ol_version=$(grep -oE '[0-9]+' /etc/oracle-release | head -1)
	fi
	ol_version="${ol_version:-8}"
	if ! dnf repolist 2>/dev/null | grep -q "ol${ol_version}_developer_EPEL"; then
		${PACKAGE_INSTALL[os_idx]} oracle-epel-release-el"${ol_version}" -y 2>/dev/null
	fi
}

# =====================================
# Function: Check system requirements (enhanced)
# Description: Verify root, internet, DNS, disk space, OS version, and install required tools
# =====================================
check_system_requirements() {
    if [[ $EUID -ne 0 ]]; then
        red "ATTENTION: Run the script as root user"
        exit 1
    fi

    # Clear package manager locks for RHEL-based systems (detect by files)
    if [[ -f /etc/redhat-release ]] || [[ -f /etc/almalinux-release ]] || [[ -f /etc/rocky-release ]] || [[ -f /etc/oracle-release ]]; then
        yellow "  Checking for dnf/yum/rpm locks ..."
        systemctl stop dnf-automatic.timer 2>/dev/null || true
        systemctl stop dnf-makecache.timer 2>/dev/null || true
        pkill -f "dnf|yum|rpm" 2>/dev/null || true
        rm -f /var/run/dnf.pid /var/lib/rpm/.rpm.lock /var/lib/rpm/__db* 2>/dev/null
        rpm --rebuilddb 2>/dev/null || true
        green "✓ RPM locks cleared"
    fi

    # Check apt/dpkg locks (Debian/Ubuntu)
    if command -v dpkg &>/dev/null; then
        if pgrep -x "apt" > /dev/null || pgrep -x "dpkg" > /dev/null || pgrep -x "apt-get" > /dev/null; then
            red "Another apt/dpkg process is running. Wait or kill it"
            exit 1
        fi
        # Also clear apt locks if present (optional)
        yellow "  Checking for apt locks ..."
        systemctl stop unattended-upgrades 2>/dev/null || true
        fuser -k /var/lib/dpkg/lock-frontend 2>/dev/null || true
        fuser -k /var/lib/dpkg/lock 2>/dev/null || true
        dpkg --configure -a 2>/dev/null || true
        green "✓ Apt locks cleared"
    fi

    # Internet check via HTTP (more reliable than ping)
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        red "No internet access (cannot ping 8.8.8.8)"
        exit 1
    fi

    # DNS resolution check
    if ! getent hosts google.com >/dev/null 2>&1 && ! host google.com >/dev/null 2>&1; then
        yellow "  Warning: DNS resolution problem (may affect certificate issuance)"
    fi

    # Disk space check (minimum 2 GB)
    local free_gb
    free_gb=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
    if [[ -z "$free_gb" ]] || [[ ${free_gb:-0} -lt 2 ]]; then
        red "Not enough free disk space (need ≥2 GB, have ${free_gb:-0}G)"
        exit 1
    fi

    # Detect OS
    local CMD=(
        "$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)"
        "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)"
        "$(lsb_release -sd 2>/dev/null)"
        "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)"
        "$(grep . /etc/redhat-release 2>/dev/null)"
        "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')"
    )
    local SYS=""
    for i in "${CMD[@]}"; do
        SYS="$i" && [[ -n $SYS ]] && break
    done

    for ((os_idx = 0; os_idx < ${#REGEX[@]}; os_idx++)); do
        if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[os_idx]} ]]; then
            SYSTEM="${RELEASE[os_idx]}"
            break
        fi
    done

    if [[ -z $SYSTEM ]]; then
        red "Your operating system is not supported!"
        exit 1
    fi

    # Fine-tuning for AlmaLinux / Rocky
    if [[ -f /etc/almalinux-release ]]; then
        SYSTEM="AlmaLinux"
    elif [[ -f /etc/rocky-release ]]; then
        SYSTEM="Rocky Linux"
    fi

    # Version checks (using grep -oE for compatibility)
    local VERSION=""
    case $SYSTEM in
        "Debian")
            VERSION=$(grep -oE 'VERSION_ID="[0-9]+"' /etc/os-release 2>/dev/null | grep -oE '[0-9]+')
            [[ -z $VERSION ]] && VERSION=$(grep -oE 'VERSION="[0-9]+"' /etc/os-release 2>/dev/null | grep -oE '[0-9]+')
            if [[ ${VERSION:-0} -lt 11 ]]; then
                red "Debian ${VERSION:-unknown} too old! Requires Debian 11 or later"
                exit 1
            fi
            ;;
        "Ubuntu")
            VERSION=$(grep -oE 'VERSION_ID="[0-9]+"' /etc/os-release 2>/dev/null | grep -oE '[0-9]+')
            if [[ ${VERSION:-0} -lt 20 ]]; then
                red "Ubuntu ${VERSION:-unknown} too old! Requires Ubuntu 20.04 or later"
                exit 1
            fi
            ;;
        "CentOS"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            VERSION=$(grep -oE '[0-9]+' /etc/os-release 2>/dev/null | head -1)
            if [[ -z "$VERSION" ]] && [[ -f /etc/centos-release ]]; then
                VERSION=$(grep -oE '[0-9]+' /etc/centos-release 2>/dev/null | head -1)
            fi
            if [[ ${VERSION:-0} -lt 8 ]]; then
                red "$SYSTEM ${VERSION:-unknown} too old! Requires version 8 or later"
                exit 1
            fi
            ;;
        "Fedora")
            VERSION=$(grep -oE 'VERSION_ID="[0-9]+"' /etc/os-release 2>/dev/null | grep -oE '[0-9]+')
            if [[ ${VERSION:-0} -lt 37 ]]; then
                red "Fedora ${VERSION:-unknown} too old! Requires Fedora 37 or later"
                exit 1
            fi
            ;;
    esac

    green "  $SYSTEM ${VERSION:-unknown}"
}

# =====================================
# Function: Install essential tools (curl, wget, openssl, tar)
# =====================================	
install_essential_tools() {	
    for cmd in "${ESSENTIAL_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            yellow "  Command '$cmd' not found. Attempting to install ..."
            case $SYSTEM in
                "Debian"|"Ubuntu")
                    apt-get update -qq && apt-get install -y -qq "$cmd" 2>/dev/null
                    ;;
                "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
                    dnf install -y "$cmd" 2>/dev/null
                    ;;
            esac
            if ! command -v "$cmd" &>/dev/null; then
                red "Failed to install '$cmd'. Please install it manually and rerun the script"
                exit 1
            fi
            green "✓ '$cmd' installed"
        fi
    done
}

# =====================================
# Function: Configure automatic updates based on OS
# =====================================
setup_auto_updates() {
    yellow "  Setting up automatic security updates ..."
    
    case $SYSTEM in
        "Debian"|"Ubuntu")
            if ! dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed"; then
                ${PACKAGE_INSTALL[os_idx]} unattended-upgrades -y 2>/dev/null
            fi
            
            cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

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
            green "  Unattended upgrades are enabled"
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            ${PACKAGE_INSTALL[os_idx]} dnf-automatic -y 2>/dev/null
            sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf 2>/dev/null
            systemctl enable --now dnf-automatic.timer 2>/dev/null
            green "  Automatic updates (dnf-automatic) are enabled"
            ;;
        *)
            yellow "  Automatic updates are not configured (ОС: $SYSTEM)"
            ;;
    esac
}

# =====================================
# Function: Setting up fail2ban with EPEL support for RHEL
# =====================================
setup_fail2ban() {
    yellow "  Configuring fail2ban to protect SSH (port: $ssh_port) ..."

    # Если порт не задан, используем 22
    local ssh_port="${ssh_port:-22}"

    # ---- Для RHEL-систем всегда включаем EPEL (если ещё не подключён) ----
    if [[ $SYSTEM == "CentOS" ]] || [[ $SYSTEM == "AlmaLinux" ]] || [[ $SYSTEM == "Rocky Linux" ]] || [[ $SYSTEM == "Oracle Linux" ]]; then
        if [[ $SYSTEM == "Oracle Linux" ]]; then
            enable_oracle_epel
        else
            # Для остальных RHEL – подключаем EPEL, если репозиторий не активен
            if ! rpm -q epel-release &>/dev/null && ! rpm -q epel-next-release &>/dev/null; then
                yellow "  Enabling EPEL repository ..."
                ${PACKAGE_INSTALL[os_idx]} epel-release -y 2>/dev/null
            fi
        fi
    fi

    # ---- Установка fail2ban, если отсутствует ----
    if ! command -v fail2ban-client &>/dev/null; then
        yellow "  Installing fail2ban ..."
        ${PACKAGE_INSTALL[os_idx]} fail2ban -y 2>/dev/null
        if ! command -v fail2ban-client &>/dev/null; then
            yellow "  fail2ban installation failed – skipping configuration"
            return 0
        fi
    fi

    # ---- Создаём каталог fail2ban ----
    mkdir -p /etc/fail2ban

    # ---- Файл jail.local – добавляем/обновляем секцию [sshd] без перезаписи ----
    local jail_local="/etc/fail2ban/jail.local"
    local jail_backup="${jail_local}.bak"

    # Создаём резервную копию, если её ещё нет
    [[ -f "$jail_local" && ! -f "$jail_backup" ]] && cp "$jail_local" "$jail_backup"

    # Выбираем подходящий banaction в зависимости от системы
    local banaction="iptables-multiport"
    if [[ $SYSTEM == "CentOS" ]] || [[ $SYSTEM == "Fedora" ]] || [[ $SYSTEM == "AlmaLinux" ]] || [[ $SYSTEM == "Rocky Linux" ]] || [[ $SYSTEM == "Oracle Linux" ]]; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            banaction="firewallcmd-ipset"
        fi
    elif [[ $SYSTEM == "Debian" ]] || [[ $SYSTEM == "Ubuntu" ]]; then
        if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
            banaction="ufw"
        fi
    fi

    # Функция для безопасного добавления/обновления секции [sshd]
    add_or_update_sshd_jail() {
        # Если секция уже существует – обновляем параметры
        if grep -q "^\[sshd\]" "$jail_local" 2>/dev/null; then
            # Обновляем порт
            sed -i "/^\[sshd\]/,/^\[.*\]/ s/^port = .*/port = $ssh_port/" "$jail_local"
            # Если строка port отсутствует, добавляем её после [sshd]
            if ! sed -n "/^\[sshd\]/,/^\[.*\]/p" "$jail_local" | grep -q "^port ="; then
                sed -i "/^\[sshd\]/a port = $ssh_port" "$jail_local"
            fi
            # Обновляем banaction
            sed -i "/^\[sshd\]/,/^\[.*\]/ s/^banaction = .*/banaction = $banaction/" "$jail_local"
            green "✓ Updated existing [sshd] jail (port: $ssh_port, banaction: $banaction)"
        else
            # Добавляем новую секцию в конец файла
            cat >> "$jail_local" << EOF

[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = $( [[ $SYSTEM == "Debian" || $SYSTEM == "Ubuntu" ]] && echo "/var/log/auth.log" || echo "/var/log/secure" )
banaction = $banaction
maxretry = 5
findtime = 600
bantime = 3600
EOF
            green "✓ Added [sshd] jail (port: $ssh_port, banaction: $banaction)"
        fi
    }

    # Если файл jail.local не существует – создаём базовый с DEFAULT и секцией sshd
    if [[ ! -f "$jail_local" ]]; then
        cat > "$jail_local" << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = $banaction

EOF
        add_or_update_sshd_jail
    else
        # Добавляем/обновляем только секцию sshd, не трогая остальное
        add_or_update_sshd_jail
    fi

    # ---- Проверяем корректность конфигурации fail2ban ----
    if ! fail2ban-client -t >/dev/null 2>&1; then
        yellow "  fail2ban configuration test failed – rolling back to backup if exists"
        if [[ -f "$jail_backup" ]]; then
            cp "$jail_backup" "$jail_local"
            yellow "  Restored previous configuration"
        fi
        return 1
    fi

    # ---- Запускаем и включаем fail2ban ----
    systemctl enable fail2ban 2>/dev/null
    systemctl restart fail2ban 2>/dev/null

    if systemctl is-active --quiet fail2ban; then
        green "✓ fail2ban is active (SSH port: $ssh_port, banaction: $banaction)"
    else
        yellow "○ fail2ban installed but not active – check logs: journalctl -u fail2ban"
        return 0
    fi
}

# =====================================
# Function: Check architecture, RAM, disk
# =====================================
check_hardware_requirements() {
    case "$(uname -m)" in
        x86_64|amd64) green "  Architecture: x86_64" ;;
        aarch64|arm64) green "  Architecture: ARM64" ;;
        *) red "  Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac
    
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    
    if [[ $TOTAL_RAM_MB -lt 1024 ]]; then
        if [[ $TOTAL_RAM_MB -lt 256 ]]; then
            red "Not enough RAM: ${TOTAL_RAM_MB}MB (minimum 256MB required)"
            exit 1
        elif [[ $TOTAL_RAM_MB -lt 512 ]]; then
            yellow "  RAM ${TOTAL_RAM_MB}MB may not be enough to compile Caddy"
        else
            green "  RAM: ${TOTAL_RAM_MB}MB"
        fi
    else
        if [[ $TOTAL_RAM_MB -ge 1024 ]]; then
			TOTAL_RAM_GB=$(( TOTAL_RAM_MB / 1024 ))
			green "  RAM: ${TOTAL_RAM_GB}GB (${TOTAL_RAM_MB}MB)"
		else
			green "  RAM: ${TOTAL_RAM_MB}MB"
		fi
    fi
    
    FREE_SPACE_MB=$(df -m / | awk 'NR==2 {print $4}')
    FREE_SPACE_GB=$((FREE_SPACE_MB / 1024))
    
    if [[ $FREE_SPACE_MB -lt 1024 ]]; then
        red "  Not enough free space: ${FREE_SPACE_MB}MB (minimum required 1GB)"
        exit 1
    else
        green "  Free space: ${FREE_SPACE_GB}GB"
    fi
}

# =====================================
# Function: Create swap file if low memory
# =====================================
setup_swap() {
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    
    if [[ $TOTAL_RAM -ge 4096 ]]; then
        green "  RAM: ${TOTAL_RAM}MB, swap not required"
        return 0
    fi
    
    if swapon --show 2>/dev/null | grep -q "/swapfile"; then
        green "  Swap already configured"
        return 0
    fi
    
    # Определяем размер swap в мегабайтах (избегаем дробей в bash)
    local SWAP_MB=0
    if [[ $TOTAL_RAM -lt 512 ]]; then
        SWAP_MB=2048   # 2 GB
    elif [[ $TOTAL_RAM -lt 1024 ]]; then
        SWAP_MB=1536   # 1.5 GB
    elif [[ $TOTAL_RAM -lt 2048 ]]; then
        SWAP_MB=1024   # 1 GB
    elif [[ $TOTAL_RAM -lt 4096 ]]; then
        SWAP_MB=2048   # 2 GB
    else
        SWAP_MB=2048   # fallback
    fi
    
    # Отображаем размер в ГБ для удобства (с поддержкой дробных через bc)
    local SWAP_SIZE_GB
    SWAP_SIZE_GB=$(echo "scale=1; $SWAP_MB/1024" | bc 2>/dev/null || echo "$((SWAP_MB/1024))")
    yellow "  Low memory detected (${TOTAL_RAM}MB). Creating ${SWAP_SIZE_GB}GB swap file ..."
    
    # Отключаем и удаляем старый swap-файл, если он существует (но не активен)
    if [[ -f /swapfile ]]; then
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
    fi
    
    # Пытаемся создать через fallocate (быстро)
    if fallocate -l ${SWAP_MB}M /swapfile 2>/dev/null; then
        chmod 600 /swapfile
        if mkswap /swapfile 2>/dev/null && swapon /swapfile 2>/dev/null; then
            if ! grep -q "^/swapfile" /etc/fstab; then
                echo "/swapfile none swap sw 0 0" >> /etc/fstab
            fi
            green "  Swap file created (${SWAP_SIZE_GB}GB / ${SWAP_MB}MB) using fallocate"
            return 0
        else
            red "  Failed to activate swap file created by fallocate"
            rm -f /swapfile
            return 1
        fi
    else
        # fallback: использовать dd (медленнее, но надёжнее)
        yellow "  fallocate failed, using dd (may take a moment) ..."
        if dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_MB 2>/dev/null; then
            chmod 600 /swapfile
            if mkswap /swapfile 2>/dev/null && swapon /swapfile 2>/dev/null; then
                if ! grep -q "^/swapfile" /etc/fstab; then
                    echo "/swapfile none swap sw 0 0" >> /etc/fstab
                fi
                green "  Swap file created (${SWAP_SIZE_GB}GB) using dd"
                return 0
            else
                red "  Failed to activate swap file created by dd"
                rm -f /swapfile
                return 1
            fi
        else
            red "  Failed to create swap file with dd"
            return 1
        fi
    fi
}

# =====================================
# Function: Install base packages
# =====================================
install_base_packages() {
    yellow "  Installing base packages ..."
    
    # Проверяем, что команда установки не пуста (защита от ошибок в массивах)
    if [[ -z "${PACKAGE_INSTALL[os_idx]}" ]]; then
        red "ERROR: PACKAGE_INSTALL[os_idx] is empty! os_idx=$os_idx, SYSTEM=$SYSTEM"
        # Fallback в зависимости от типа ОС
        case $SYSTEM in
            Debian|Ubuntu)
                PACKAGE_INSTALL[os_idx]="apt -y install"
                ;;
            CentOS|Fedora|AlmaLinux|"Rocky Linux"|"Oracle Linux")
                PACKAGE_INSTALL[os_idx]="yum -y install"
                ;;
            *)
                red "Unsupported system for fallback: $SYSTEM"
                exit 1
                ;;
        esac
        green "  Fixed: PACKAGE_INSTALL[os_idx]='${PACKAGE_INSTALL[os_idx]}'"
    fi
    
    if [[ $SYSTEM == "CentOS" ]] && [[ ${VERSION:-0} -ge 8 ]]; then
        ${PACKAGE_UPDATE[os_idx]} 2>/dev/null || true
    elif [[ $SYSTEM != "CentOS" ]]; then
        ${PACKAGE_UPDATE[os_idx]}
    fi
    
    if [[ $SYSTEM == "CentOS" ]] || [[ $SYSTEM == "Fedora" ]] || [[ $SYSTEM == "AlmaLinux" ]] || [[ $SYSTEM == "Rocky Linux" ]]; then
        if ! rpm -q epel-release &>/dev/null && ! rpm -q epel-next-release &>/dev/null; then
            yellow "  Connecting the EPEL repository ..."
            ${PACKAGE_INSTALL[os_idx]} epel-release -y 2>/dev/null
        fi
    fi
    
    if [[ $SYSTEM == "Oracle Linux" ]]; then
        enable_oracle_epel
    fi
    
    # Устанавливаем общие пакеты
    ${PACKAGE_INSTALL[os_idx]} "${COMMON_PACKAGES[@]}"
    
    # Устанавливаем специфичные для дистрибутива пакеты
    case $SYSTEM in
        Debian|Ubuntu)
            ${PACKAGE_INSTALL[os_idx]} "${DEBIAN_PACKAGES[@]}"
            ;;
        CentOS|Fedora|AlmaLinux|"Rocky Linux"|"Oracle Linux")
            ${PACKAGE_INSTALL[os_idx]} "${RHEL_PACKAGES[@]}"
            ;;
        *)
            yellow "  Unknown system, skipping OS-specific packages"
            ;;
    esac
    
    green "  Basic packages are installed"
}

# =====================================
# Function: Configure firewall with port 80 check
# =====================================
configure_firewall() {
    yellow "  Configuring firewall (SSH port: $ssh_port) ..."
    
    case $SYSTEM in
        "Debian"|"Ubuntu")
            if ! command -v ufw &>/dev/null; then
                ${PACKAGE_INSTALL[os_idx]} ufw -y 2>/dev/null
            fi
            sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw 2>/dev/null
            ufw --force reset 2>/dev/null
            ufw default deny incoming 2>/dev/null
            ufw default allow outgoing 2>/dev/null
            ufw allow "$ssh_port"/tcp 2>/dev/null
            ufw allow 80/tcp 2>/dev/null
            ufw allow 443/tcp 2>/dev/null
            ufw allow 443/udp 2>/dev/null
            ufw --force enable 2>/dev/null
            green "  UFW firewall configured (SSH port: $ssh_port)"
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            if ! command -v firewall-cmd &>/dev/null; then
                ${PACKAGE_INSTALL[os_idx]} firewalld -y 2>/dev/null
            fi
            systemctl enable --now firewalld 2>/dev/null
            firewall-cmd --permanent --add-port="$ssh_port"/tcp 2>/dev/null
            firewall-cmd --permanent --add-port=80/tcp 2>/dev/null
            firewall-cmd --permanent --add-port=443/tcp 2>/dev/null
            firewall-cmd --permanent --add-port=443/udp 2>/dev/null
            firewall-cmd --reload 2>/dev/null
            green "  firewalld configured (SSH port: $ssh_port)"
            ;;
        *)
            yellow "  Unknown OS — firewall not configured automatically"
            ;;
    esac

    # ---- Check if port 80 is actually open, if not – suggest to open ----
    if ! is_port_open_in_firewall 80; then
        echo ""
        yellow "○ Port 80 is currently closed in firewall"
        yellow "  Let's Encrypt requires port 80 open for automatic certificate renewal"
        read -rp "  Open port 80 now? [Y/n]: " open_port
        if [[ "$open_port" =~ ^[Yy]$ ]] || [[ -z "$open_port" ]]; then
            case $SYSTEM in
                "Debian"|"Ubuntu")
                    ufw allow 80/tcp
                    ufw --force reload 2>/dev/null
                    ;;
                "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
                    firewall-cmd --permanent --add-port=80/tcp
                    firewall-cmd --reload 2>/dev/null
                    ;;
            esac
            green "✓ Port 80 opened. Certificate renewal will work automatically"
        else
            yellow "○ Port 80 remains closed. You will need to renew certificates manually or open it later"
        fi
    else
        green "✓ Port 80 is open in firewall (good for ACME renewals)"
    fi
}

# =====================================
# Function: Change SSH port
# Description: Changes SSH port and validates configuration before restart
# =====================================
change_ssh_port() {
    CURRENT_SSH_PORT=$(ss -tlnp | awk '/sshd/ {split($4,a,":"); print a[2]}' | head -n1)
    [[ -z "$CURRENT_SSH_PORT" ]] && CURRENT_SSH_PORT=22
    
    if [[ $ssh_port -eq $CURRENT_SSH_PORT ]]; then
        yellow "○ SSH port already set to $ssh_port (no changes needed)"
        return 0
    fi
    
    yellow "  Changing SSH port from $CURRENT_SSH_PORT to $ssh_port ..."
	
	# Проверяем, не занят ли новый порт
    if ss -tlnp | grep -q ":${ssh_port} "; then
        red "✗ Port ${ssh_port} is already in use by another process"
        return 1
    fi
    
    sed -i "s/^#Port $CURRENT_SSH_PORT/Port $ssh_port/" /etc/ssh/sshd_config
    sed -i "s/^Port $CURRENT_SSH_PORT/Port $ssh_port/" /etc/ssh/sshd_config
    
    if ! grep -q "^Port $ssh_port" /etc/ssh/sshd_config; then
        echo "Port $ssh_port" >> /etc/ssh/sshd_config
    fi
    
    if sshd -t; then
        restart_ssh
        green "✓ SSH port changed from $CURRENT_SSH_PORT to $ssh_port"
        echo ""
        yellow "○ Current session remains active on port $CURRENT_SSH_PORT"
        local current_ip="$SERVER_IP"
        if [[ -z "$current_ip" ]] || [[ "$current_ip" == "unknown" ]]; then
            current_ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "unknown")
        fi
        if [[ "$current_ip" != "unknown" ]]; then
            yellow "○ Next time connect using: ssh -p $ssh_port root@$current_ip"
        else
            yellow "○ Next time connect using: ssh -p $ssh_port root@<your-server-ip>"
        fi
    else
        red "✗ SSH config test failed! Port not changed"
        return 1
    fi
}

# =====================================
# Function: Install latest Go (always overwrites, no prompts)
# =====================================
install_go() {
    yellow "  Installing latest stable Go ..."

    LATEST_GO_VERSION=$(curl -s --max-time 10 https://go.dev/VERSION?m=text | head -n 1)
    if [[ -z "$LATEST_GO_VERSION" ]]; then
        red "  Failed to get latest Go version. Check connection."
        exit 1
    fi

    GO_VERSION="${LATEST_GO_VERSION#go}"
    green "  Latest version: $GO_VERSION"

    # Определяем архитектуру
    if [[ "$(uname -m)" == "x86_64" ]]; then
        ARCH="amd64"
    elif [[ "$(uname -m)" == "aarch64" ]]; then
        ARCH="arm64"
    else
        red "  Unsupported architecture: $(uname -m)"
        exit 1
    fi

    DOWNLOAD_URL="https://go.dev/dl/${LATEST_GO_VERSION}.linux-${ARCH}.tar.gz"

    # Удаляем старую установку Go (если есть)
    if [[ -d /usr/local/go ]]; then
        yellow "  Removing old /usr/local/go ..."
        rm -rf /usr/local/go
    fi

    # Скачиваем и распаковываем
	for i in 1 2 3; do
		yellow "  Downloading go ${GO_VERSION} for linux/${ARCH} (attempt ${i}) ..."
		wget -q --show-progress "$DOWNLOAD_URL" -O /tmp/go.tar.gz
		if [[ ! -s /tmp/go.tar.gz ]]; then
			red "  Download failed"
			exit 1
		fi
		break
	done

    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz

    # Добавляем PATH в .bashrc, если ещё нет
    if ! grep -q "/usr/local/go/bin" ~/.bashrc; then
		# shellcheck disable=SC2016
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    fi
    export PATH=$PATH:/usr/local/go/bin

    if ! command -v go &>/dev/null; then
        red "  Go installation failed"
        exit 1
    fi

    green "  Go ${GO_VERSION} installed successfully"
}

# =====================================
# Function: Auto-detect domain via reverse DNS (PTR) using DoH with fallback to dig
# =====================================
auto_detect_domain() {
    local server_ip="$1"
    local ptr_domain=""
    
    if [[ -z "$server_ip" ]] || [[ "$server_ip" == "unknown" ]]; then
        yellow "○ No valid server IP provided, skipping auto-detection" >&2
        return 1
    fi
    
    yellow "→ Attempting to detect domain via reverse DNS (PTR) for IP: $server_ip" >&2
    
    local reverse_ip
    reverse_ip=$(echo "$server_ip" | awk -F. '{print $4"."$3"."$2"."$1".in-addr.arpa"}')
    
    if command -v curl &>/dev/null; then
        ptr_domain=$(doh_query "$reverse_ip" "PTR")
    fi
    
    if [[ -z "$ptr_domain" ]] && command -v dig &>/dev/null; then
        ptr_domain=$(dig -x "$server_ip" +short 2>/dev/null | head -1 | awk '{print $1}' | sed 's/\.$//')
    fi
    
    if [[ -z "$ptr_domain" ]]; then
        yellow "○ No PTR record found for $server_ip" >&2
        return 1
    fi
    
    if [[ "$ptr_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        yellow "○ PTR record points to IP address ($ptr_domain), ignoring" >&2
        return 1
    fi
    
    local resolved_ip=""
    if command -v curl &>/dev/null; then
        resolved_ip=$(doh_query "$ptr_domain" "A")
    fi
    if [[ -z "$resolved_ip" ]] && command -v dig &>/dev/null; then
        resolved_ip=$(dig +short "$ptr_domain" 2>/dev/null | head -1)
    fi
    
    if [[ -n "$resolved_ip" ]] && [[ "$resolved_ip" != "$server_ip" ]]; then
        yellow "○ PTR domain $ptr_domain resolves to $resolved_ip, not our IP. Skipping auto-detection" >&2
        return 1
    fi
    
    echo "$ptr_domain"
    return 0
}

# =====================================
# Function: Check if IPv4 address belongs to CIDR network
# Parameters: $1 - IP address, $2 - CIDR (e.g., "192.0.2.0/24")
# Returns: 0 if true, 1 otherwise
# =====================================
ip_in_cidr() {
    local ip="$1"
    local cidr="$2"
    local ip_dec=0 net_dec=0 mask_dec=0
    local IFS=.
    
    # Convert IP to decimal
    for octet in $ip; do
        ip_dec=$(( (ip_dec << 8) + octet ))
    done
    
    # Extract network and mask
    local network="${cidr%/*}"
    local mask="${cidr#*/}"
    for octet in $network; do
        net_dec=$(( (net_dec << 8) + octet ))
    done
    
    # Calculate mask
    mask_dec=$(( 0xffffffff << (32 - mask) & 0xffffffff ))
    
    if (( (ip_dec & mask_dec) == (net_dec & mask_dec) )); then
        return 0
    else
        return 1
    fi
}

# =====================================
# Function: Check if domain uses Cloudflare proxy (orange cloud)
# Parameters: $1 - domain name
# Returns: 0 if proxied through Cloudflare, 1 otherwise
# =====================================
check_cloudflare_proxy() {
    local domain="$1"
    local domain_ip=""
    
    if [[ -z "$domain" ]]; then
        return 1
    fi
    
    # Get A record using dig (or fallback to host)
    domain_ip=$(dig +short "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    if [[ -z "$domain_ip" ]]; then
        domain_ip=$(host -t A "$domain" 2>/dev/null | grep "has address" | head -1 | awk '{print $NF}')
    fi
    [[ -z "$domain_ip" ]] && return 1
    
    # Cloudflare IPv4 prefixes (updated 2026)
    # Source: https://www.cloudflare.com/ips-v4
    local cf_prefixes=(
        "103.21.244.0/22" "103.22.200.0/22" "103.31.4.0/22" "104.16.0.0/13"
        "104.24.0.0/14" "108.162.192.0/18" "131.0.72.0/22" "141.101.64.0/18"
        "162.158.0.0/15" "172.64.0.0/13" "173.245.48.0/20" "188.114.96.0/20"
        "190.93.240.0/20" "197.234.240.0/22" "198.41.128.0/17" "199.27.128.0/21"
    )
    
    for prefix in "${cf_prefixes[@]}"; do
        if ip_in_cidr "$domain_ip" "$prefix"; then
            return 0
        fi
    done
    return 1
}

# =====================================
# Function: Perform DNS query via Cloudflare DoH (DNS over HTTPS)
# Parameters: $1 - domain name, $2 - record type (A, PTR, etc.)
# Returns: prints IP address(es) or PTR value, one per line; returns 0 if success
# =====================================
doh_query() {
    local name="$1"
    local type="$2"
    local url="https://cloudflare-dns.com/dns-query?name=${name}&type=${type}"
    local response
    
    response=$(curl -s --max-time 5 -H "accept: application/dns-json" "$url" 2>/dev/null)
    if [[ -z "$response" ]]; then
        return 1
    fi
    
    if [[ "$type" == "A" ]]; then
        echo "$response" | grep -oE '"data":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | sed 's/"data":"//;s/"//' | head -1
        return 0
    elif [[ "$type" == "PTR" ]]; then
        # Извлекаем все PTR записи, берём первую, убираем точку в конце
        echo "$response" | grep -oE '"data":"[^"]+"' | sed 's/"data":"//;s/"//;s/\.$//' | head -1
        return 0
    fi
    return 1
}

# =====================================
# Function: Find first free port from a list for given protocol
# Parameters: $1 - protocol ("tcp" or "udp"), $2... - list of ports
# Returns: first free port number, or 0 if none found
# =====================================
get_free_port() {
    local proto="$1"
    shift
    local ports=("$@")
    
    for port in "${ports[@]}"; do
        if [[ "$proto" == "tcp" ]]; then
            # Проверяем, слушает ли какой-либо процесс TCP-порт
            if ! ss -tlnp 2>/dev/null | grep -q ":${port} "; then
                # Дополнительно проверяем, нет ли сокетов в состоянии TIME_WAIT
                if ! ss -tln 2>/dev/null | grep -q ":${port} "; then
                    echo "$port"
                    return 0
                fi
            fi
        elif [[ "$proto" == "udp" ]]; then
            if ! ss -ulnp 2>/dev/null | grep -q ":${port} "; then
                echo "$port"
                return 0
            fi
        fi
    done
    echo "0"
    return 1
}

# =====================================
# Function: Check if TCP port is open in firewall (UFW or firewalld)
# Parameters: $1 - port number
# Returns: 0 if allowed/opened, 1 otherwise
# =====================================
is_port_open_in_firewall() {
    local port=$1
    case $SYSTEM in
        "Debian"|"Ubuntu")
            if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
                ufw status | grep -q "$port/tcp.*ALLOW" && return 0
            fi
            # fallback: проверим iptables (если ufw не активен)
            iptables -L INPUT -n 2>/dev/null | grep -q "dpt:$port" && return 0
            return 1
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
                firewall-cmd --list-ports 2>/dev/null | grep -q "$port/tcp" && return 0
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# =====================================
# Function: User input parameters
# =====================================
input_parameters() {
    echo ""
    echo -e " ${BLUE}. . . . . . . . . . . . .${PLAIN}"
    yellow "    Common Configuration"
    echo -e " ${BLUE}. . . . . . . . . . . . .${PLAIN}"
    
	if [[ -f /root/naive/runtime.env ]]; then
		# shellcheck source=/dev/null
		source /root/naive/runtime.env
		yellow "○ Found existing configuration"
		echo ""
		green "  Domain      :  $domain"
		green "  Proxy port  :  $proxyport"
		green "  SSH port    :  $ssh_port"
		green "  Username    :  $proxyname"
		green "  Password    :  $proxypwd"
		[[ -n "$email" ]] && green "  Email       :  $email"
		[[ -n "$remote_server" ]] && green "  Remote server: $remote_server"
        echo -e " ${BLUE}. . . . . . . . . . . . .${PLAIN}"
        echo ""
		
		while true; do
			read -rp "  Do you want to use these settings? [Y/n]: " use_saved
			use_saved=$(echo "$use_saved" | tr '[:upper:]' '[:lower:]' | xargs)
			
			case $use_saved in
				n|no)
					yellow "○ OK, let's reconfigure everything"
					unset ssh_port proxyport domain email proxyname proxypwd remote_server
					break
					;;
				""|y|yes)
					green "✓ Using saved configuration"
					SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")
					return 0
					;;
				*)
					red "✗ Please answer y or n"
					continue
					;;
			esac
		done
	fi
    
    # --- SSH port ---
    while true; do
        echo ""
        blue "→ SSH configuration:"
        echo "  [1] 22    (Default — standard SSH port)"
        echo "  [2] Custom port (range 1024-65535)"
        echo ""
        read -rp "$(green "  Your choice [1-2]: ")" ssh_choice

        case $ssh_choice in
            1)
                ssh_port=22
                green "✓ SSH port set to: 22"
                break
                ;;
            2)
                while true; do
                    read -rp "$(yellow "  Enter custom SSH port (1024-65535): ")" ssh_port_input
                    if [[ "$ssh_port_input" =~ ^[0-9]+$ ]] && [ "$ssh_port_input" -ge 1024 ] && [ "$ssh_port_input" -le 65535 ]; then
                        ssh_port="$ssh_port_input"
                        green "✓ SSH port set to: $ssh_port"
                        break 2
                    else
                        red "✗ Error: Invalid port — must be number between 1024 and 65535"
                        continue
                    fi
                done
                ;;
            *)
                red "✗ Invalid choice — please select 1 or 2"
                continue
                ;;
        esac
    done

    # --- NaiveProxy port ---
    while true; do    
        echo ""
        blue "→ NaiveProxy port selection:"
        echo "  [1] 443  (Recommended — best camouflage)"
        echo "  [2] 8443 (Alternative — often allowed in corporate networks)"
        echo "  [3] Custom port (range 1024-65535)"
        echo ""
        read -rp "$(green "  Your choice [1-3]: ")" port_choice

        case $port_choice in
            1)
                proxyport=443
                if ss -tlnp | awk -v p=":${proxyport}" '$4 ~ p {exit 0} END {exit 1}'; then
                    red "✗ Port $proxyport is already in use by another process!"
                    # Предлагаем альтернативные порты
                    local alt_port
                    alt_port=$(get_free_port "tcp" 8443 2087 2096 8080)
                    if [[ "$alt_port" != "0" ]]; then
                        echo ""
                        yellow "○ Alternative free ports found: $alt_port"
                        read -rp "Use port $alt_port instead? [Y/n]: " use_alt
                        if [[ "$use_alt" =~ ^[Yy]$ ]] || [[ -z "$use_alt" ]]; then
                            proxyport="$alt_port"
                            green "✓ Using alternative port $proxyport"
                            break
                        else
                            yellow "  Please select another port manually:"
                            continue
                        fi
                    else
                        yellow "  No free alternative ports found. Please select another port manually:"
                        continue
                    fi
                else
                    green "✓ Port $proxyport selected and available"
                    break
                fi
                ;;
            2)
                proxyport=8443
                if ss -tlnp | awk -v p=":${proxyport}" '$4 ~ p {exit 0} END {exit 1}'; then
                    red "✗ Port $proxyport is already in use by another process!"
                    local alt_port
                    alt_port=$(get_free_port "tcp" 443 2087 2096 8080)
                    if [[ "$alt_port" != "0" ]]; then
                        echo ""
                        yellow "○ Alternative free ports found: $alt_port"
                        read -rp "Use port $alt_port instead? [Y/n]: " use_alt
                        if [[ "$use_alt" =~ ^[Yy]$ ]] || [[ -z "$use_alt" ]]; then
                            proxyport="$alt_port"
                            green "✓ Using alternative port $proxyport"
                            break
                        else
                            yellow "  Please select another port manually:"
                            continue
                        fi
                    else
                        yellow "  No free alternative ports found. Please select another port manually:"
                        continue
                    fi
                else
                    green "✓ Port $proxyport selected and available"
                    break
                fi
                ;;
            3)
                while true; do
                    read -rp "$(yellow "  Enter custom port (1024-65535): ")" proxyport
                    if [[ ! "$proxyport" =~ ^[0-9]+$ ]] || [ "$proxyport" -lt 1024 ] || [ "$proxyport" -gt 65535 ]; then
                        red "✗ Error: Invalid port — must be number between 1024 and 65535"
                        continue
                    fi
                    
                    if ss -tlnp | awk -v p=":${proxyport}" '$4 ~ p {exit 0} END {exit 1}'; then
                        red "✗ Port $proxyport is already in use by another process!"
                        # Для кастомного порта тоже предложим альтернативы
                        local alt_port
                        alt_port=$(get_free_port "tcp" 8443 2087 2096 8080)
                        if [[ "$alt_port" != "0" ]]; then
                            echo ""
                            yellow "○ Alternative free ports found: $alt_port"
                            read -rp "Use port $alt_port instead? [Y/n]: " use_alt
                            if [[ "$use_alt" =~ ^[Yy]$ ]] || [[ -z "$use_alt" ]]; then
                                proxyport="$alt_port"
                                green "✓ Using alternative port $proxyport"
                                break 2
                            else
                                yellow "  Please enter another custom port:"
                                continue
                            fi
                        else
                            yellow "  No free alternative ports found. Please enter another custom port:"
                            continue
                        fi
                    else
                        green "✓ Port $proxyport selected and available"
                        break 2
                    fi
                done
                ;;
            *)
                red "✗ Invalid choice — please select 1, 2, or 3"
                continue
                ;;
        esac
    done

    # --- Domain input with auto-detection ---
    # Получаем внешний IP один раз
    SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || curl -s --max-time 5 ipinfo.io/ip 2>/dev/null)

    # Ручной ввод, если домен ещё не определён
    while [[ -z "$domain" ]]; do
        echo ""
        read -rp "$(blue "→ Enter your domain (e.g., example.com): ")" domain
        
        if [[ -z "$domain" ]]; then
            red "✗ The domain cannot be empty!"
            continue
        fi
        
        if ! echo "$domain" | grep -qE '^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$'; then
            red "✗ Incorrect domain format — use example.com"
            domain=""
            continue
        fi
        
        yellow "→ Checking DNS ..."
        DOMAIN_IP=$(dig +short "$domain" | head -1)
        
        if [[ -z "$DOMAIN_IP" ]]; then
            red "✗ Domain $domain does not resolve to an IP address"
            yellow "→ Fix your DNS records and try again"
            domain=""
            continue
        fi
        
        if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
            red "✗ Domain $domain points to $DOMAIN_IP, but server IP is $SERVER_IP"
            red "→ Fix your A record and try again"
            domain=""
            continue
        fi
        
        green "✓ DNS check passed: $domain → $DOMAIN_IP"
        
        # +++ Cloudflare proxy check +++
        if check_cloudflare_proxy "$domain"; then
            echo ""
            yellow "═══════════════════════════════════════════════════════════════"
            yellow "        Cloudflare Proxy Detected (Orange Cloud)"
            yellow "═══════════════════════════════════════════════════════════════"
            echo ""
            yellow "  Domain ${domain} resolves to Cloudflare IP: ${DOMAIN_IP}"
            echo ""
            yellow "  !!! WARNING !!!"
            yellow "  Cloudflare proxy (orange cloud) WILL break NaiveProxy tunnel"
            yellow "  - WebSocket connections will be terminated by Cloudflare"
            yellow "  - The proxy will not work"
            echo ""
            yellow "  RECOMMENDED ACTION:"
            yellow "  1. Go to Cloudflare Dashboard → DNS"
            yellow "  2. Find the A record for ${domain}"
            yellow "  3. Click the orange cloud → change to grey cloud (DNS only)"
            yellow "  4. Wait 1-2 minutes for DNS propagation"
            echo ""
            yellow "  After switching to grey cloud, re-run the installation"
            yellow "═══════════════════════════════════════════════════════════════"
            echo ""
            read -rp "  Continue anyway? (NOT recommended) [y/N]: " cf_continue
            if [[ ! "$cf_continue" =~ ^[Yy]$ ]]; then
                red "  Installation aborted. Please disable Cloudflare proxy and try again"
                domain=""   # reset domain to force re-entry
                continue
            else
                yellow "  Continuing with Cloudflare proxy enabled – connection may fail"
            fi
        fi
        # +++ End of Cloudflare check +++
        
    done

    # --- Email ---
    while true; do
        echo ""
        read -rp "$(blue "→ Enter email for Let's Encrypt certificate: ")" email
        
        if [[ -z "$email" ]]; then
            red "✗ Email cannot be empty!"
            continue
        fi
        
        if ! echo "$email" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
            red "✗ Incorrect email format — use user@example.com"
            continue
        fi
        
        green "✓ Email is valid: $email"
        break
    done

    # --- Remote server for mutual imitation ---
    echo ""
    read -rp "$(blue "→ Enter remote server for mutual traffic imitation (IP or domain, leave empty to skip): ")" remote_server_input
    
    if [[ -n "$remote_server_input" ]]; then
        # Валидация: только IPv4 или домен (RFC 1035)
        if [[ "$remote_server_input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
           [[ "$remote_server_input" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
            remote_server="$remote_server_input"
            green "✓ Remote server set: $remote_server"
        else
            yellow "○ Invalid format (only IP or domain allowed), mutual imitation disabled"
            remote_server=""
        fi
    else
        remote_server=""
    fi

    # --- Generate admin credentials ---
    proxyname=$(openssl rand -hex 12)
    proxypwd=$(openssl rand -hex 16)
    green "✓ Admin credentials generated"
    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                  Review Your Settings"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    green "  SSH port:      $ssh_port"
    green "  Proxy port:    $proxyport"
    green "  Domain:        $domain"
    green "  Email:         $email"
    green "  Username:      $proxyname"
    green "  Password:      $proxypwd"
    echo ""
    
    while true; do
        read -rp "  Do you want to proceed with these settings? [Y/n]: " confirm
        case $confirm in
            [Yy]*|"")
                green "✓ Configuration confirmed"
                break
                ;;
			[Nn]*)
				yellow "○ Configuration cancelled. Starting over ..."
				input_parameters
				return 0
                ;;
            *)
                red "✗ Please answer y or n"
                continue
                ;;
        esac
    done
    
    echo ""
    green "✓ Configuration completed successfully!"
    echo ""
    
    save_runtime_config
}

build_caddy() {
    export GOBIN=/root/go/bin
    export PATH=$PATH:/usr/local/go/bin:$GOBIN

    mkdir -p /root/tmp
    export TMPDIR=/root/tmp

    # Убедимся, что strings доступна
    if ! command -v strings &>/dev/null; then
        yellow "  Installing binutils (strings) ..."
        case $SYSTEM in
            "Debian"|"Ubuntu") apt-get update -qq && apt-get install -y -qq binutils 2>/dev/null ;;
            *) dnf install -y binutils 2>/dev/null || yum install -y binutils 2>/dev/null ;;
        esac
    fi

    if ! command -v xcaddy &>/dev/null; then
        green "→ Installing xcaddy ..."
        for i in 1 2 3; do
            go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest && break
            sleep 3
        done
        if ! command -v xcaddy &>/dev/null; then
            red "✗ Failed to install xcaddy"
            return 1
        fi
        green "✓ xcaddy installed"
    fi

    echo ""
    yellow "→ Building Caddy (usually 1-5 minutes) ..."

    # Резервное копирование
    if [[ -f /usr/bin/caddy ]]; then
        cp /usr/bin/caddy /usr/bin/caddy.bak
        green "✓ Backup created"
    fi

    local logfile="/tmp/caddy-build-$$.log"
	
    xcaddy build \
    --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/rushiiMachine/caddy-ja3 \
    --with github.com/rushiiMachine/caddy-deflate \
    --with github.com/ueffel/caddy-brotli \
    --with github.com/mholt/caddy-l4 \
    > "$logfile" 2>&1 &
	
    local build_pid=$!

    local spin='-\|/'
    local i=0
    while kill -0 $build_pid 2>/dev/null; do
        printf "\r   %s Building Caddy ... " "${spin:i++%${#spin}:1}"
        sleep 0.2
    done
    printf "\r                              \r"

    wait $build_pid
    local build_status=$?

    if [[ $build_status -eq 0 ]] && [[ -f ./caddy ]]; then
        # Проверка через strings (безопасно, не запускает бинарник)
        if strings ./caddy 2>/dev/null | grep -qi "forwardproxy"; then
            mv -f ./caddy /usr/bin/caddy
            chmod +x /usr/bin/caddy
            green "✓ Caddy build successful (forwardproxy plugin detected)"
            rm -f "$logfile"
            rm -f /usr/bin/caddy.bak
        else
            red "✗ Built Caddy does NOT contain forwardproxy plugin (strings check)"
            rm -f ./caddy
            if [[ -f /usr/bin/caddy.bak ]]; then
                mv /usr/bin/caddy.bak /usr/bin/caddy
                green "✓ Restored previous Caddy binary"
            fi
            return 1
        fi
    else
        red "✗ Caddy build failed!"
        yellow "  Log: $logfile"
        tail -20 "$logfile"
        if [[ -f /usr/bin/caddy.bak ]]; then
            mv /usr/bin/caddy.bak /usr/bin/caddy
            green "✓ Restored previous Caddy binary"
        fi
        return 1
    fi
}

# =====================================
# Function: Validate Caddyfile and show detailed error on failure
# Parameters: $1 - path to Caddyfile (default: /etc/caddy/Caddyfile)
# Returns: 0 if valid, 1 otherwise
# =====================================
validate_caddyfile() {
    local caddyfile="${1:-/etc/caddy/Caddyfile}"
    local quiet="${2:-false}"
    
    if [[ ! -f "$caddyfile" ]]; then
        [[ "$quiet" == "false" ]] && red "✗ Caddyfile not found: $caddyfile"
        return 1
    fi
    
    # Определяем путь к caddy
    local caddy_bin=""
    if [[ -x /usr/bin/caddy ]]; then
        caddy_bin="/usr/bin/caddy"
    elif command -v caddy &>/dev/null; then
        caddy_bin=$(command -v caddy)
    else
        [[ "$quiet" == "false" ]] && red "✗ caddy binary not found"
        return 1
    fi
    
    local error_output
    error_output=$("$caddy_bin" validate --config "$caddyfile" --adapter caddyfile 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        [[ "$quiet" == "false" ]] && green "✓ Caddyfile validation passed"
        return 0
    else
        [[ "$quiet" == "false" ]] && {
            red "✗ Caddyfile validation failed!"
            echo ""
            yellow "  Error details:"
            # Показываем не более 20 строк, чтобы не завалить экран
            echo "$error_output" | head -20 | sed 's/^/    /'
            [[ $(echo "$error_output" | wc -l) -gt 20 ]] && echo "    ... (truncated)"
            echo ""
            yellow "  Check line numbers and syntax in: $caddyfile"
        }
        return 1
    fi
}

# =====================================
# Function: Add/remove basic_auth user in Caddyfile
# Parameters: $1 - action (add/del), $2 - username, $3 - password
# Returns: 0 on success, 1 on failure
# =====================================
modify_caddyfile() {
    local action="$1"
    local username="$2"
    local password="$3"
    local caddyfile="/etc/caddy/Caddyfile"

    [[ ! -f "$caddyfile" ]] && { red "✗ Caddyfile not found"; return 1; }

    cp "$caddyfile" "$caddyfile.bak"

    if [[ "$action" == "add" ]]; then
        if grep -q "basic_auth $username " "$caddyfile"; then
            yellow "○ User $username already exists"
            rm -f "$caddyfile.bak"
            return 0
        fi
        # Вставить строку после forward_proxy {
        sed -i "/^[[:space:]]*forward_proxy[[:space:]]*{/a \\    basic_auth $username $password" "$caddyfile"
    elif [[ "$action" == "del" ]]; then
        sed -i "/basic_auth $username /d" "$caddyfile"
    else
        red "✗ Unknown action: $action"
        return 1
    fi

    if ! validate_caddyfile "$caddyfile" "true"; then
        red "✗ Invalid Caddyfile after modification, restoring backup"
        mv "$caddyfile.bak" "$caddyfile"
        return 1
    fi

    rm -f "$caddyfile.bak"
    return 0
}

# =====================================
# Function: Restore all users from registry into Caddyfile (without restarting after each)
# =====================================
restore_users_from_registry() {
    local registry="/root/naive/registry.txt"
    [[ ! -f "$registry" ]] && return 0

    # Проверяем, есть ли уже пользователи в Caddyfile (кроме админа)
    local existing_users
    existing_users=$(grep -c "basic_auth" /etc/caddy/Caddyfile 2>/dev/null || echo 0)
    if [[ $existing_users -gt 1 ]]; then
        yellow "○ Existing users found in Caddyfile, skipping restore"
        return 0
    fi

    green "  Restoring users from registry ..."
    local users_to_add=()
    while IFS='|' read -r id username password name created; do
        # Пропускаем пустые строки и заголовки
        [[ -z "$username" || "$username" == "Username" ]] && continue
        username=$(echo "$username" | xargs)
        password=$(echo "$password" | xargs)
        if [[ -n "$username" && -n "$password" ]]; then
            # Не добавляем администратора (он уже есть)
            if [[ "$username" != "$proxyname" ]]; then
                users_to_add+=("$username" "$password")
            fi
        fi
    done < "$registry"

    if [[ ${#users_to_add[@]} -eq 0 ]]; then
        green "  No additional users to restore"
        return 0
    fi

    # Добавляем всех пользователей одной операцией (через временный файл, чтобы не перезапускать Caddy много раз)
    local caddyfile="/etc/caddy/Caddyfile"
    cp "$caddyfile" "$caddyfile.bak"

    for ((i=0; i<${#users_to_add[@]}; i+=2)); do
        local u="${users_to_add[i]}"
        local p="${users_to_add[i+1]}"
        # Вставляем строку после forward_proxy { (с тем же отступом)
        sed -i "/^[[:space:]]*forward_proxy[[:space:]]*{/a \\    basic_auth $u $p" "$caddyfile"
    done

    # Проверяем валидность изменённого Caddyfile
    if ! validate_caddyfile "$caddyfile" "true"; then
        red "✗ Invalid Caddyfile after restoring users, rolling back"
        mv "$caddyfile.bak" "$caddyfile"
        return 1
    fi

    rm -f "$caddyfile.bak"
    green "✓ All users restored from registry"
    return 0
}

# =====================================
# Function: Creating configuration files
# =====================================
create_configs() {
    cat > /etc/caddy/Caddyfile << EOF
{
    order forward_proxy before file_server
    order ja3 before respond
    admin 127.0.0.1:2019
    email ${email}
    
	ja3 {
		sort_extensions
	}
}

:${proxyport}, ${domain}:${proxyport} {
    ja3
    encode br zstd deflate gzip
    
    header {
        X-Powered-By "Express"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "camera=(), microphone=(), geolocation=()"
        -Server
    }

    # WebSocket endpoint emulation
    route /ws-proxy {
        respond 426
    }

    forward_proxy {
        basic_auth ${proxyname} ${proxypwd}
        hide_ip
        hide_via
        probe_resistance
    }

    @post method POST
    handle @post {
        handle /contact* {
            header Location "/contact/thank-you.html"
            respond "" 302
        }
    }

    file_server {
        root /var/www/html
    }

    handle_errors {
        rewrite * /404.html
        root /var/www/html
        file_server
    }

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

    # Форматируем Caddyfile в стандартном стиле
    caddy fmt --overwrite /etc/caddy/Caddyfile

    mkdir -p /root/naive
    cat <<EOF > /root/naive/naive-client.json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://${proxyname}:${proxypwd}@${domain}:${proxyport}",
  "log": ""
}
EOF

    url="naive+https://${proxyname}:${proxypwd}@${domain}:${proxyport}?padding=true#Naive-${domain}"
    echo "$url" > /root/naive/naive-url.txt
    
    # Права для web-корня (без caddy)
    chmod 755 /var/www/html
    
    # Устанавливаем безопасные права на конфигурацию
    chmod 600 /root/naive/naive-client.json
    chmod 600 /root/naive/naive-url.txt
}

# =====================================
# Function: Create a systemd service (runs as root)
# =====================================
create_systemd_service() {
    systemctl stop caddy 2>/dev/null
    sleep 2
    
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
		# ---- Validate Caddyfile before starting ----
		if ! validate_caddyfile "/etc/caddy/Caddyfile"; then
			red "✗ Caddyfile validation failed. Cannot start Caddy."
			return 1
		fi	
    sleep 2
    systemctl start caddy
}

# =====================================
# Function: Enable BBR
# =====================================
enable_bbr() {
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        grep -q "^net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        grep -q "^net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        green "  BBR is On"
    fi
}

# =====================================
# Function: Disable unnecessary services
# =====================================
disable_unnecessary_services() {
    yellow "  Disabling unnecessary services for security ..."
    
    local services=("avahi-daemon" "bluetooth" "cups" "cups-browsed" "ModemManager" "packagekit")
    
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
    yellow "  Applying sysctl optimizations for proxy ..."
    
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
    green "  Sysctl optimizations applied"
}

# =====================================
# Function: Increase system limits for high-load performance
# =====================================
increase_limits() {
    yellow "  Increasing system limits for high-load performance ..."

    local LIMIT_VALUE=2097152
    local limits_file="/etc/security/limits.conf"
    local backup_file="${limits_file}.bak"

    # Создаём резервную копию (один раз)
    if [[ ! -f "$backup_file" ]]; then
        cp "$limits_file" "$backup_file"
    fi

    # Функция добавления строки, если её нет
    add_limit() {
        local domain="$1"
        local type="$2"
        local item="$3"
        local value="$4"
        local line="${domain} ${type} ${item} ${value}"
        if ! grep -q "^${domain}[[:space:]]\+${type}[[:space:]]\+${item}[[:space:]]\+${value}\$" "$limits_file"; then
            echo "$line" >> "$limits_file"
            green "  ✓ Added: $line"
        else
            yellow "  ○ Already present: $line"
        fi
    }

    # Добавляем нужные лимиты
    add_limit "*"  "soft" "nofile" "$LIMIT_VALUE"
    add_limit "*"  "hard" "nofile" "$LIMIT_VALUE"
    add_limit "root" "soft" "nofile" "$LIMIT_VALUE"
    add_limit "root" "hard" "nofile" "$LIMIT_VALUE"

    # Проверяем и увеличиваем общесистемный лимит fs.file-max при необходимости
    local current_fs_max
    current_fs_max=$(sysctl -n fs.file-max 2>/dev/null)
    if [[ -n "$current_fs_max" ]] && [[ $current_fs_max -lt $LIMIT_VALUE ]]; then
        yellow "  ○ System fs.file-max ($current_fs_max) is lower than desired limit ($LIMIT_VALUE). Increasing..."
        echo "fs.file-max = $LIMIT_VALUE" > /etc/sysctl.d/99-naiveproxy-file-max.conf
        sysctl -p /etc/sysctl.d/99-naiveproxy-file-max.conf 2>/dev/null
        green "  ✓ fs.file-max increased to $LIMIT_VALUE"
    fi

    green "  ✓ System limits increased (nofile = $LIMIT_VALUE)"
    echo "    (Changes take effect after next login or reboot)"
}

# =====================================
# Function: Wait for SSL certificate (with backup fallback)
# =====================================
wait_for_ssl_certificate() {
    local domain=$1
    local max_wait=70
    local waited=0

    # Пробуем восстановить из бэкапа (быстро)
    if restore_certificates "true"; then
        green "✓ Certificates restored from backup"
        systemctl restart caddy
        sleep 5
        if systemctl is-active --quiet caddy && check_certificate_valid "$domain"; then
            green "✓ Restored certificate is working"
            return 0
        else
            yellow "○ Restored certificate not responding or Caddy not running, will try to obtain fresh one"
        fi
    else
        yellow "○ No valid backup or restore failed, waiting for fresh certificate..."
    fi

    # Убедимся, что Caddy запущен (если нет, запускаем)
    if ! systemctl is-active --quiet caddy; then
        systemctl start caddy
        sleep 3
        if ! systemctl is-active --quiet caddy; then
            red "✗ Caddy failed to start"
            return 1
        fi
    fi

    echo ""
    yellow "○ Waiting for SSL certificate to become accessible ..."
    echo ""

    while [[ $waited -lt $max_wait ]]; do
        # Проверяем, не появился ли уже сертификат
        if check_certificate_valid "$domain"; then
            echo ""
            green "✓ SSL certificate obtained and working"
            return 0
        fi

        # Ранний выход при критических ошибках в логах Caddy (без -P)
        local recent_errors
        recent_errors=$(journalctl -u caddy --since "60 seconds ago" --no-pager 2>/dev/null | grep -iE "rateLimited|rejectedIdentifier|too many certificates|identifier is disallowed")
        if [[ -n "$recent_errors" ]]; then
            # Игнорируем rejectedIdentifier, если он относится к ZeroSSL
            if echo "$recent_errors" | grep -qi "rejectedIdentifier" && echo "$recent_errors" | grep -qi "zerossl"; then
                # Только ZeroSSL отклонил – не прерываем ожидание
                :
            else
                echo ""
                red "✗ Certificate issuance blocked (rate limit or domain rejected)"
                # Извлекаем время снятия лимита (без -P)
                local retry_after
                retry_after=$(journalctl -u caddy --since "60 seconds ago" --no-pager 2>/dev/null | grep -oE 'retry after [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | sed 's/retry after //' | tail -1)
                if [[ -n "$retry_after" ]]; then
                    yellow "○ Let's Encrypt rate limit resets at: $retry_after UTC"
                    yellow "○ You can restart Caddy after this time to obtain the certificate (menu option 6)"
                fi
                journalctl -u caddy --since "60 seconds ago" --no-pager | grep -iE "error|rateLimit|rejected" | tail -5
                return 1
            fi
        fi

        printf "."
        sleep 2
        waited=$((waited + 2))
    done

    echo ""
    red "✗ Failed to obtain or restore SSL certificate within ${max_wait} seconds"
    yellow "  ○ Check logs: journalctl -u caddy -n 50"
    yellow "  ○ Or try again later (Let's Encrypt limit: 5 per week)"
    return 1
}

# =====================================
# Function: Show enhanced installation checklist with error/warning counting
# =====================================
show_install_checklist() {
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                    Installation Checklist"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""

    local fail=0
    local warn=0

    # ---- Caddy service ----
    if systemctl is-active --quiet caddy; then
        green "✓ Caddy service: running"
    else
        red "✗ Caddy service: NOT running"
        ((fail++))
    fi

    # ---- Ports (SSH, 80, 443) ----
    if ss -tlnp | grep -q ":$ssh_port "; then
		green "✓ Port $ssh_port (SSH): listening"
	else
		yellow "○ Port $ssh_port (SSH): not listening"
		((warn++))
	fi
	if ss -tlnp | grep -q ":80 "; then
		green "✓ Port 80: listening"
	else
		yellow "○ Port 80: not listening"
		((warn++))
	fi
	if ss -tlnp | grep -q ":443 "; then
		green "✓ Port 443: listening"
	else
		yellow "○ Port 443: not listening"
		((warn++))
	fi

    # ---- Firewall and port 80 reachability for ACME ----
    if is_port_open_in_firewall 80; then
        green "✓ Port 80: open in firewall (ACME renewals possible)"
    else
        red "✗ Port 80: NOT open in firewall — automatic certificate renewal will fail"
        ((fail++))
    fi

    case $SYSTEM in
        "Debian"|"Ubuntu")
            if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
                if ufw status | grep -q "$ssh_port/tcp.*ALLOW"; then
					green "✓ UFW: port $ssh_port (SSH) allowed"
				else
					yellow "○ UFW: port $ssh_port (SSH) rule missing"
					((warn++))
				fi
				if ufw status | grep -q "80/tcp.*ALLOW"; then
					green "✓ UFW: port 80 allowed"
				else
					yellow "○ UFW: port 80 rule missing"
					((warn++))
				fi
				if ufw status | grep -q "443/tcp.*ALLOW"; then
					green "✓ UFW: port 443 allowed"
				else
					yellow "○ UFW: port 443 rule missing"
					((warn++))
				fi
            else
                yellow "○ UFW: not active"
                ((warn++))
            fi
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
                if firewall-cmd --list-ports 2>/dev/null | grep -q "$ssh_port/tcp"; then
					green "✓ firewalld: port $ssh_port (SSH) allowed"
				else
					yellow "○ firewalld: port $ssh_port (SSH) not allowed"
					((warn++))
				fi
				if firewall-cmd --list-ports 2>/dev/null | grep -q "80/tcp"; then
					green "✓ firewalld: port 80 allowed"
				else
					yellow "○ firewalld: port 80 not allowed"
					((warn++))
				fi
				if firewall-cmd --list-ports 2>/dev/null | grep -q "443/tcp"; then
					green "✓ firewalld: port 443 allowed"
				else
					yellow "○ firewalld: port 443 not allowed"
					((warn++))
				fi
            else
                yellow "○ firewalld: not active"
                ((warn++))
            fi
            ;;
        *)
            yellow "○ Firewall: unknown system"
            ((warn++))
            ;;
    esac

    # ---- SSL certificate ----
    local cert_file
    cert_file=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    if [[ -n "$cert_file" ]]; then
        local cert_expiry
        cert_expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        local issuer
        issuer=$(openssl x509 -issuer -noout -in "$cert_file" 2>/dev/null | sed 's/issuer=//')
        local expiry_epoch
        expiry_epoch=$(date -d "$cert_expiry" +%s 2>/dev/null)
        local now_epoch
        now_epoch=$(date +%s)
        local days_left
        days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
        if [[ $days_left -gt 0 ]]; then
            green "✓ SSL certificate: valid until $cert_expiry ($days_left days left)"
            echo -e "  ${GREEN}Issuer:${PLAIN} $issuer"
        else
            red "✗ SSL certificate: EXPIRED"
            ((fail++))
        fi
    else
        red "✗ SSL certificate: not obtained"
        ((fail++))
    fi

    # ---- Client config ----
	if [[ -f /root/naive/naive-client.json ]]; then
		green "✓ Client config: /root/naive/naive-client.json"
	else
		red "✗ Client config: missing"
		((fail++))
	fi
	if [[ -f /root/naive/naive-url.txt ]]; then
		green "✓ Import link: /root/naive/naive-url.txt"
	else
		red "✗ Import link: missing"
		((fail++))
	fi

    # ---- fail2ban ----
    if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban; then
        local banned
        banned=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print $4}')
        green "✓ fail2ban: active (banned: ${banned:-0})"
    else
        yellow "○ fail2ban: not active"
        ((warn++))
    fi

    # ---- BBR ----
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        green "✓ BBR: enabled"
    else
        yellow "○ BBR: not enabled"
        ((warn++))
    fi

    # ---- NaiveGuard watchdog ----
    if systemctl is-active --quiet naiveguard.timer 2>/dev/null; then
        green "✓ NaiveGuard watchdog: active"
    else
        yellow "○ NaiveGuard: not installed"
        ((warn++))
    fi

    # ---- Auto security updates ----
    if systemctl is-active --quiet unattended-upgrades 2>/dev/null || systemctl is-active --quiet dnf-automatic.timer 2>/dev/null; then
        green "✓ Auto security updates: enabled"
    else
        yellow "○ Auto updates: not configured"
        ((warn++))
    fi

    # ---- Activity simulation (WebGhost) ----
    if systemctl is-active --quiet webghost-activity.timer 2>/dev/null; then
        green "✓ Activity simulation: active (hourly)"
    else
        yellow "○ Activity simulation: not running"
        ((warn++))
    fi

    # ---- Mutual imitation (optional) ----
    if [[ -n "${remote_server:-}" ]]; then
        green "✓ Mutual imitation: active (${remote_server})"
    else
        blue "○ Mutual imitation: not configured (optional)"
    fi

    # ---- External reachability of port 443 ----
    local server_ip
    server_ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "unknown")
    if [[ "$server_ip" != "unknown" ]]; then
        if timeout 3 bash -c "echo >/dev/tcp/$server_ip/443" 2>/dev/null; then
            green "✓ Port 443: reachable from internet"
        else
            red "✗ Port 443: not reachable"
            ((fail++))
        fi
    else
        yellow "○ Could not determine external IP"
        ((warn++))
    fi

    # ---- Final summary ----
    echo ""
    if [[ $fail -eq 0 ]] && [[ $warn -eq 0 ]]; then
        green "═══════════════════════════════════════════════════════════════"
        green "✓ All checks passed successfully!"
        green "═══════════════════════════════════════════════════════════════"
    elif [[ $fail -eq 0 ]]; then
        yellow "═══════════════════════════════════════════════════════════════"
        yellow "○ Installation has $warn warning(s) (non-critical)"
        yellow "═══════════════════════════════════════════════════════════════"
    else
        red "═══════════════════════════════════════════════════════════════"
        red "✗ Installation has $fail error(s) and $warn warning(s)"
        red "═══════════════════════════════════════════════════════════════"
    fi

    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    echo -e " ${BLUE}Bash:${PLAIN} ${BASH_VERSION}  ${BLUE}Kernel:${PLAIN} $(uname -r)"
	echo -e " ${BLUE}Host:${PLAIN} $(hostname)"
    echo -e " ${BLUE}OS:${PLAIN} ${SYSTEM:-unknown} ${VERSION:-}  ${BLUE}Arch:${PLAIN} $(uname -m)"
    echo -e " ${BLUE}Uptime:${PLAIN} $(uptime -p | sed 's/up //')"  
    yellow "═══════════════════════════════════════════════════════════════"
}

# =====================================
# Function: NaiveProxy Installation
# =====================================
install_naiveproxy() {
    show_header
    
	if is_naive_installed; then
		yellow "  NaiveProxy is already installed!"
		while true; do
			echo ""
			read -rp "  Do you want to reinstall? [Y/n]: " reinstall
			case $reinstall in
				[Nn]*)
					green "  Installation cancelled"
					show_footer
					return 0
					;;
				[Yy]*|"")
					yellow "○ Reinstalling NaiveProxy ..."
					break
					;;
				*)
					red "✗ Please answer y or n"
					continue
					;;
			esac
		done
	fi
    
    green "  Starting installation of NaiveProxy ..."
    local current_ssh_port=22
    
    yellow "\n  Checking system requirements ..."
    check_system_requirements
	install_essential_tools
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
		if ! install_webghost; then
			red "✗ WebGhost installation failed – aborting"
			exit 1
		fi
    create_configs
	
	if ! create_systemd_service; then
		red "✗ Failed to create Caddy service. Installation aborted."
		exit 1
	fi
		# ---- Проверяем, что порт 80 реально работает (не только открыт в фаерволе) ----
		sleep 3
		if curl -s -o /dev/null -I -w "%{http_code}" http://127.0.0.1/ | grep -q "30[0-9]"; then
			green "✓ Port 80 is actively responding (HTTP redirect works)"
		else
			yellow "○ Port 80 does not respond as expected (Caddy may have issues)"
			yellow "  Check: curl -I http://127.0.0.1/"
		fi
    enable_bbr

    if systemctl is-active --quiet caddy; then
        green "\n✓ NaiveProxy successfully installed and running!"
        green "✓ Client configuration saved in /root/naive/"
        
        # Пробуем восстановить сертификат из бэкапа
        local skip_cert_wait=false
        if restore_certificates; then
            yellow "○ Certificates restored from backup, skipping issuance"
            systemctl restart caddy
            sleep 3
			
		if ! systemctl is-active --quiet caddy; then
			red "✗ Caddy failed to restart! Check: journalctl -u caddy -n 30"
			return 1
		fi
			
            if check_certificate_valid "$domain"; then
                green "✓ Restored certificate is valid, continuing ..."
                skip_cert_wait=true
            fi
        fi
        
        if [[ "$skip_cert_wait" != true ]]; then
            wait_for_ssl_certificate "$domain"
        fi
        
        # Делаем бэкап сертификатов
        if check_certificate_valid "$domain"; then
            backup_certificates
        fi
          
		setup_systemd_updates
		setup_naiveguard
	 setup_custom_prompt
		
		show_install_checklist
		
		# ===== ВОТ ЗДЕСЬ ДОБАВЛЕНО ВОССТАНОВЛЕНИЕ ПОЛЬЗОВАТЕЛЕЙ =====
		restore_users_from_registry
		systemctl restart caddy
		# ============================================================
        
        if [[ $ssh_port -ne $current_ssh_port ]]; then
            echo ""
            yellow "═══════════════════════════════════════════════════════════════"
            yellow "                   SSH Port Changed"
            yellow "═══════════════════════════════════════════════════════════════"
            echo ""
            yellow "○ SSH port changed from $current_ssh_port to $ssh_port"
            yellow "○ Your current connection remains active on port $current_ssh_port"
            echo ""
            red "✗ NEXT TIME CONNECT USING:"
            red "    ssh -p $ssh_port root@$SERVER_IP"
            echo ""
            yellow "○ Make sure your firewall allows port $ssh_port"
            yellow "○ If you lose access, use VPS console to check"
            echo ""
            yellow "═══════════════════════════════════════════════════════════════"
        fi
    else
        red "Error starting Caddy! Check logs: journalctl -u caddy -n 50"
        exit 1
    fi
    
    show_footer
}

# =====================================
# Function: Remove NaiveProxy completely
# =====================================
uninstall_naiveproxy() {
    show_header
    
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                 UNINSTALL NaiveProxy Manager"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    yellow "This will remove:"
    echo -e "  ${RED}• NaiveProxy (Caddy with forwardproxy)${PLAIN} – service, binary, configs"
    echo -e "  ${RED}• SSL certificates (Let's Encrypt)${PLAIN} – except backup in /root/naive"
    echo -e "  ${RED}• WebGhost${PLAIN} – timer, website, binary, config"
    echo -e "  ${RED}• Caddy auto-update systemd timer and scripts${PLAIN}"
    echo -e "  ${RED}• NaiveGuard watchdog timer and scripts${PLAIN}"
    echo ""
    yellow "The following will be KEPT by default (you can choose to remove):"
    echo -e "  ${GREEN}• Go installation (/usr/local/go)${PLAIN} – always kept"
    echo -e "  ${GREEN}• Swap file (if created)${PLAIN} – optional removal"
    echo -e "  ${GREEN}• Custom bash prompt (if added)${PLAIN} – optional removal"
    echo -e "  ${GREEN}• /root/naive directory (backup, configs, users)${PLAIN} – optional removal"
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    
    read -rp "Are you sure you want to UNINSTALL NaiveProxy Manager? [Y/n]: " confirm_uninstall
    if [[ -z "$confirm_uninstall" ]] || [[ "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        green "  Proceeding with uninstall ..."
    else
        green "  Uninstall cancelled"
        show_footer
        return 0
    fi
    
    yellow "  Stopping all services ..."
    
    # =================================================================
    # 1. Остановка всех связанных systemd сервисов и таймеров
    # =================================================================
    for unit in caddy caddy-update.timer caddy-update.service \
                webghost-activity.timer webghost-activity.service \
                naiveguard.timer naiveguard.service; do
        systemctl stop "$unit" 2>/dev/null
        systemctl disable "$unit" 2>/dev/null
    done
    
    # =================================================================
    # 2. Удаление WebGhost (через его собственную команду, если есть)
    # =================================================================
    if command -v webghost &>/dev/null; then
        yellow "  Removing WebGhost via webghost uninstall-all ..."
        webghost uninstall-all 2>/dev/null
    else
        yellow "  WebGhost binary not found, performing manual cleanup ..."
        rm -f /usr/local/bin/webghost-activity.sh
        rm -f /var/log/webghost-activity.log
        rm -f /etc/logrotate.d/webghost-activity
        rm -rf /var/www/html/*
    fi
    rm -f /etc/webghost.conf
    rm -f /usr/local/bin/webghost
    
    # =================================================================
    # 3. Удаление Caddy auto-update (системный таймер и скрипты)
    # =================================================================
    yellow "  Removing Caddy auto-update systemd timer ..."
    rm -f /etc/systemd/system/caddy-update.{service,timer}
    rm -f /usr/local/bin/naive-update
    rm -f /var/log/naive-update.log
    rm -f /etc/logrotate.d/naive-update
    
    # =================================================================
    # 4. Удаление NaiveGuard watchdog
    # =================================================================
    yellow "  Removing NaiveGuard watchdog ..."
    rm -f /etc/systemd/system/naiveguard.{service,timer}
    rm -f /usr/local/bin/naiveguard.sh
    rm -f /var/log/naiveguard.log
    rm -f /etc/logrotate.d/naiveguard
    rm -f /var/lock/naiveguard.lock 2>/dev/null
    
    # =================================================================
    # 5. Удаление Caddy (NaiveProxy core)
    # =================================================================
    yellow "  Removing Caddy service and binaries ..."
    rm -rf /etc/caddy
    rm -f /usr/bin/caddy
    rm -f /usr/local/bin/caddy
    rm -rf /var/lib/caddy 2>/dev/null
    rm -rf /root/.local/share/caddy 2>/dev/null
    rm -rf /root/tmp /root/go /root/.cache/go-build
    
    # Удаление PATH Go из .bashrc (если строка была добавлена)
	# shellcheck disable=SC2016
    sed -i '/export PATH=\$PATH:\/usr\/local\/go\/bin/d' ~/.bashrc
    
    # =================================================================
    # 6. Опциональные удаления (по умолчанию НЕТ)
    # =================================================================
    echo ""
    read -rp "Remove configuration backup (/root/naive) as well? [y/N]: " remove_backup
    if [[ "$remove_backup" =~ ^[Yy]$ ]]; then
        rm -rf /root/naive
        green "✓ Configuration backup removed"
    else
        green "✓ Configuration backup kept at /root/naive/"
    fi
    
    if swapon --show 2>/dev/null | grep -q "/swapfile"; then
        echo ""
        read -rp "Remove swapfile (/swapfile) created by installer? [y/N]: " remove_swap
        if [[ "$remove_swap" =~ ^[Yy]$ ]]; then
            swapoff /swapfile 2>/dev/null
            rm -f /swapfile
            sed -i '/\/swapfile/d' /etc/fstab
            green "✓ Swapfile removed"
        else
            yellow "○ Swapfile kept"
        fi
    fi
    
    if grep -q "Custom invitation from Kordan" ~/.bashrc 2>/dev/null; then
        echo ""
        read -rp "Remove custom bash prompt (Kordan style) from ~/.bashrc? [y/N]: " remove_prompt
        if [[ "$remove_prompt" =~ ^[Yy]$ ]]; then
            sed -i '/#Custom invitation from Kordan/d' ~/.bashrc
            sed -i '/PS1=.*Kordan.*/d' ~/.bashrc
            green "✓ Custom prompt removed"
        else
            yellow "○ Custom prompt kept"
        fi
    fi
    
    # =================================================================
    # 7. Перезагрузка systemd
    # =================================================================
    systemctl daemon-reload
    
    # =================================================================
    # 8. Финальное сообщение (без лишних инструкций)
    # =================================================================
    green "✓ NaiveProxy removed!"
    echo ""
    echo -e "${YELLOW}Note:${PLAIN} Go (/usr/local/go) was not removed to avoid damaging other projects"
    echo -e "To remove Go manually: ${YELLOW}rm -rf /usr/local/go${PLAIN}"
    echo -e "Firewall rules (UFW/firewalld) for ports 80/443/$ssh_port were not modified – please review if needed."
    
    show_footer
}

# =====================================
# Function: Installation Check
# =====================================
is_naive_installed() {
    [[ -f /usr/bin/caddy ]] && [[ -f /etc/systemd/system/caddy.service ]] && [[ -f /root/naive/naive-client.json ]]
    return $?
}

# =====================================
# Function: Show client configuration
# =====================================
show_config() {
    show_header
    
    if ! is_naive_installed; then
        yellow "  NaiveProxy is not installed! Please install it first (step 1)"
        show_footer
        return 0
    fi
    
    if [[ -f /root/naive/runtime.env ]]; then
		# shellcheck source=/dev/null
        source /root/naive/runtime.env
    else
        yellow "○ Configuration file not found, some values may be missing"
    fi
    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                    Client Configuration"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if [[ -f /root/naive/naive-client.json ]]; then
        echo -e "${GREEN}JSON format:${PLAIN}"
        echo ""
        cat /root/naive/naive-client.json
        echo ""
    else
        yellow "○ JSON config file not found at /root/naive/naive-client.json"
    fi
    
    if [[ -f /root/naive/naive-url.txt ]]; then
        echo -e "${GREEN}Import link:${PLAIN}"
        echo ""
        cat /root/naive/naive-url.txt
        echo ""
    else
        yellow "○ Import link file not found at /root/naive/naive-url.txt"
    fi
    
    echo -e "${GREEN}Server:${PLAIN}    $domain"
    echo -e "${GREEN}Port:${PLAIN}      $proxyport"
    echo -e "${GREEN}Username:${PLAIN}  $proxyname"
    echo -e "${GREEN}Password:${PLAIN}  $proxypwd"
    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if command -v qrencode &>/dev/null && [[ -f /root/naive/naive-url.txt ]]; then
        green "  QR code for importing to your smartphone:"
        echo ""
        qrencode -t ANSIUTF8 "$(cat /root/naive/naive-url.txt)" 2>/dev/null || yellow "○ QR code generation error"
    elif ! command -v qrencode &>/dev/null; then
        yellow "○ Tip: Install 'qrencode' to generate QR codes"
    fi
    
    show_footer
}

# =====================================
# Function: Display user details in unified format
# Parameters: $1 - ID, $2 - username, $3 - password, $4 - name, $5 - created date
# Uses global: domain, proxyport
# =====================================
show_user_details() {
    local id="$1"
    local username="$2"
    local password="$3"
    local name="$4"
    local created="$5"
    local user_dir
	user_dir="/root/naive/users/user_$(printf "%03d" "$id")_${username}"
    local json_file="$user_dir/config.json"
    local url_file="$user_dir/url.txt"
    local url=""

    if [[ -f "$url_file" ]]; then
        url=$(cat "$url_file")
    else
        url="naive+https://${username}:${password}@${domain}:${proxyport}?padding=true#Naive-${name}"
    fi

    echo ""
    blue "═══════════════════════════════════════════════════════════════"
    green "                  User Configuration: $name"
    blue "═══════════════════════════════════════════════════════════════"
    echo ""

    if [[ -f "$json_file" ]]; then
        echo -e "${GREEN}JSON format:${PLAIN}"
        echo ""
        cat "$json_file"
        echo ""
    else
        yellow "○ JSON config file not found for this user"
    fi

    if [[ -f "$url_file" ]]; then
        echo -e "${GREEN}Import link:${PLAIN}"
        echo ""
        cat "$url_file"
        echo ""
    else
        echo -e "${GREEN}Import link:${PLAIN}"
        echo "$url"
        echo ""
    fi

    echo -e "${GREEN}Name:${PLAIN}       $name"
    echo -e "${GREEN}ID:${PLAIN}         $id"
    echo -e "${GREEN}Created:${PLAIN}    $created"
    echo ""
    echo -e "${GREEN}Server:${PLAIN}     ${domain}"
    echo -e "${GREEN}Port:${PLAIN}       ${proxyport}"
    echo -e "${GREEN}Username:${PLAIN}   $username"
    echo -e "${GREEN}Password:${PLAIN}   $password"

    echo ""
    blue "═══════════════════════════════════════════════════════════════"

    if command -v qrencode &>/dev/null && [[ -f "$url_file" ]]; then
        green "  QR code for importing to your smartphone:"
        echo ""
        qrencode -t ANSIUTF8 "$(cat "$url_file")" 2>/dev/null || yellow "○ QR code generation error"
    elif command -v qrencode &>/dev/null && [[ -n "$url" ]]; then
        green "  QR code for importing to your smartphone:"
        echo ""
        qrencode -t ANSIUTF8 "$url" 2>/dev/null || yellow "○ QR code generation error"
    elif ! command -v qrencode &>/dev/null; then
        yellow "○ Tip: Install 'qrencode' to generate QR codes"
    fi

    blue "═══════════════════════════════════════════════════════════════"
}

# =====================================
# Function: Show user registry
# =====================================
show_user_registry() {
    show_header
    
    if ! is_naive_installed; then
        yellow "  NaiveProxy is not installed!"
        show_footer
        return 0
    fi

    load_runtime_config
    
    blue "═══════════════════════════════════════════════════════════════"
    green "                      User Registry"
    blue "═══════════════════════════════════════════════════════════════"
    
    # Шапка таблицы
    echo -e "  ${GREEN}ID${PLAIN}   ${BLUE}|${PLAIN}  ${GREEN}Name${PLAIN}                          ${BLUE}|${PLAIN} ${GREEN}Username${PLAIN} ${BLUE}|${PLAIN}  ${GREEN}Created${PLAIN}"
    echo -e "${BLUE}───────┼────────────────────────────────┼──────────┼───────────${PLAIN}"
    
    if [[ -f /root/naive/registry.txt ]]; then
        while IFS='|' read -r id username password name created; do
            # Убираем пробелы
            id=$(echo "$id" | xargs)
            username=$(echo "$username" | xargs)
            name=$(echo "$name" | xargs)
            created=$(echo "$created" | xargs)
            
            local short_username="${username:0:8}"
            local short_name="${name:0:28}"
            local padded_id
            padded_id=$(printf "%4s" "$id")
            local name_padding
            name_padding=$(printf '%*s' $((30 - ${#short_name})) "")
            local user_padding
            user_padding=$(printf '%*s' $((8 - ${#short_username})) "")
                        
            echo -e "  ${padded_id} ${BLUE}|${PLAIN} ${short_name}${name_padding} ${BLUE}|${PLAIN} ${short_username}${user_padding} ${BLUE}|${PLAIN} ${created}"
        done < /root/naive/registry.txt
    fi
    
    blue "═══════════════════════════════════════════════════════════════"
    echo ""
    local total_users=0
    if [[ -f /root/naive/registry.txt ]]; then
        total_users=$(wc -l < /root/naive/registry.txt 2>/dev/null || echo 0)
    fi
    echo -e " ${GREEN}Total users:${PLAIN} $total_users"
    echo ""
    
    # Опция просмотра деталей
    read -rp "Enter ID to view full details (or 0 to skip): " view_id
    
    if [[ "$view_id" != "0" ]] && [[ -n "$view_id" ]]; then
        local user_data
        user_data=$(grep "^[[:space:]]*${view_id}[[:space:]]*|" /root/naive/registry.txt 2>/dev/null)
        
        if [[ -z "$user_data" ]]; then
            red "✗ User not found"
        else
            IFS='|' read -r id username password name created <<< "$user_data"
            id=$(echo "$id" | xargs)
            username=$(echo "$username" | xargs)
            password=$(echo "$password" | xargs)
            name=$(echo "$name" | xargs)
            created=$(echo "$created" | xargs)
            
            echo ""
            show_user_details "$id" "$username" "$password" "$name" "$created"
        fi
    fi
    
    show_footer
}

# =====================================
# Function: Add new user
# =====================================
add_new_user() {
    show_header
    
    if ! is_naive_installed; then
        yellow "  NaiveProxy is not installed!"
        show_footer
        return 0
    fi
    
    load_runtime_config
    
    # Проверяем, что конфигурация загружена
	if ! validate_config; then
		yellow "  Please reinstall NaiveProxy or restore configuration"
		show_footer
		return 1
	fi
    
    blue "═══════════════════════════════════════════════════════════════"
    green "                      Add New User"
    blue "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Ввод имени пользователя с защитой (3 попытки)
    local user_name=""
    local attempts=0
    local max_attempts=3
    
    while true; do
        if [[ $attempts -ge $max_attempts ]]; then
            red "\nMaximum attempts $max_attempts exceeded. Returning to menu ..."
            sleep 1
            show_footer
            return 0
        fi
        
        read -rp "User name (e.g., 'John' or 'Анна'): " user_name
        
        if [[ -z "$user_name" ]]; then
            attempts=$((attempts + 1))
            yellow "  Name cannot be empty. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if [[ ${#user_name} -lt 2 ]]; then
            attempts=$((attempts + 1))
            yellow "  Name must be at least 2 characters. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if [[ "$user_name" =~ [\|\\\&\;\`\$\(\)] ]]; then
            attempts=$((attempts + 1))
            yellow "  Name contains invalid characters. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if [[ -f /root/naive/registry.txt ]]; then
            if awk -F'|' -v name="$user_name" '$4 ~ "^[[:space:]]*" name "[[:space:]]*$"' /root/naive/registry.txt 2>/dev/null | grep -q .; then
                attempts=$((attempts + 1))
                yellow "  User '$user_name' already exists. Attempt $attempts of $max_attempts"
                continue
            fi
        fi
        
        echo ""
        read -rp "Confirm user name '$user_name'? [Y/n]: " confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]] || [[ -z "$confirm" ]]; then
            break
        else
            yellow "  ○ Re-enter user name"
            echo ""
            continue
        fi
    done
    
    # Генерируем учётные данные
    local username
    username=$(openssl rand -hex 4)
    local password
    password=$(openssl rand -hex 12)
    
    # Определяем следующий ID
    local next_id=1
    if [[ -f /root/naive/registry.txt ]] && [[ -s /root/naive/registry.txt ]]; then
        next_id=$(($(tail -1 /root/naive/registry.txt | cut -d'|' -f1 | xargs) + 1))
    fi
    
    local created_date
    created_date=$(date +%Y-%m-%d)
    
    # --- Атомарное обновление Caddyfile через вспомогательную функцию ---
    if ! modify_caddyfile "add" "$username" "$password"; then
        red "✗ Failed to update Caddyfile. User not added"
        return 1
    fi
    
    # Перезапускаем Caddy и проверяем
    if ! restart_caddy; then
        red "✗ Caddy failed to restart after adding user. Rolling back ..."
        # Откатываем изменения Caddyfile
        modify_caddyfile "del" "$username" "$password" >/dev/null 2>&1
		restart_caddy true >/dev/null 2>&1
        return 1
    fi
    
    # --- Создаём данные пользователя ---
    local user_dir
	user_dir="/root/naive/users/user_$(printf "%03d" "$next_id")_${username}"
    mkdir -p "$user_dir"
    
    cat > "$user_dir/config.json" << EOF
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://${username}:${password}@${domain}:${proxyport}",
  "log": ""
}
EOF
    
    local url="naive+https://${username}:${password}@${domain}:${proxyport}?padding=true#Naive-${user_name}"
    echo "$url" > "$user_dir/url.txt"
    
    chmod 600 "$user_dir/config.json"
    chmod 600 "$user_dir/url.txt"
    
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$url" > "$user_dir/qr.txt" 2>/dev/null
        [[ -f "$user_dir/qr.txt" ]] && chmod 600 "$user_dir/qr.txt"
    fi
    
    echo "$next_id | $username | $password | $user_name | $created_date" >> /root/naive/registry.txt
    
    # Финальный вывод
    echo ""
    green "✓ User '$user_name' added!"
    show_user_details "$next_id" "$username" "$password" "$user_name" "$created_date"
    show_footer
}

# =====================================
# Function: Remove user
# =====================================
remove_user() {
    while true; do
        show_header
        
        if ! is_naive_installed; then
            yellow "  NaiveProxy is not installed!"
            show_footer
            return 0
        fi
        
        load_runtime_config
		
		if ! validate_config; then
			yellow "  Please reinstall NaiveProxy or restore configuration"
			show_footer
			return 1
		fi
        
        blue "═══════════════════════════════════════════════════════════════"
        green "                      Remove User"
        blue "═══════════════════════════════════════════════════════════════"
        
        if [[ -f /root/naive/registry.txt ]]; then
            echo -e "  ${GREEN}ID${PLAIN}   ${BLUE}|${PLAIN}  ${GREEN}Name${PLAIN}                          ${BLUE}|${PLAIN} ${GREEN}Username${PLAIN} ${BLUE}|${PLAIN}  ${GREEN}Created${PLAIN}"
            echo -e "${BLUE}───────┼────────────────────────────────┼──────────┼───────────${PLAIN}"
            
            while IFS='|' read -r id username password name created; do
                id=$(echo "$id" | xargs)
                username=$(echo "$username" | xargs)
                name=$(echo "$name" | xargs)
                created=$(echo "$created" | xargs)
                
                local short_username="${username:0:8}"
                local short_name="${name:0:28}"
                local padded_id
                padded_id=$(printf "%4s" "$id")
                local name_padding
                name_padding=$(printf '%*s' $((30 - ${#short_name})) "")
                local user_padding
                user_padding=$(printf '%*s' $((8 - ${#short_username})) "")
                            
                echo -e "  ${padded_id} ${BLUE}|${PLAIN} ${short_name}${name_padding} ${BLUE}|${PLAIN} ${short_username}${user_padding} ${BLUE}|${PLAIN} ${created}"
            done < /root/naive/registry.txt
        else
            yellow "  No users found"
            echo ""
            read -rp "Press Enter to return to menu ..."
            show_footer
            return 0
        fi
        
        echo ""
        yellow "═══════════════════════════════════════════════════════════════"
        
        read -rp "Enter ID to remove (or 0 to return to menu): " remove_id
        
        if [[ "$remove_id" == "0" ]] || [[ -z "$remove_id" ]]; then
            green "  Returning to menu ..."
            break
        fi
        
        local user_data
        user_data=$(grep "^[[:space:]]*${remove_id}[[:space:]]*|" /root/naive/registry.txt 2>/dev/null)
        if [[ -z "$user_data" ]]; then
            red "✗ User not found"
            read -rp "Press Enter to continue ..."
            continue
        fi
        
        IFS='|' read -r id username password name created <<< "$user_data"
        id=$(echo "$id" | xargs)
        username=$(echo "$username" | xargs)
        password=$(echo "$password" | xargs)
        name=$(echo "$name" | xargs)
        
        echo ""
        yellow "  Remove user '$name' (ID: $id)?"
        read -rp "Type 'YES' to confirm: " confirm
        
        if [[ "$confirm" != "YES" ]]; then
            green "  Cancelled"
            read -rp "Press Enter to continue ..."
            continue
        fi
        
        # --- Атомарное удаление из Caddyfile ---
        if ! modify_caddyfile "del" "$username" "$password"; then
            red "✗ Failed to update Caddyfile. User not removed"
            read -rp "Press Enter to continue ..."
            continue
        fi
        
        # Перезапускаем Caddy и проверяем
        if ! restart_caddy; then
            red "✗ Caddy failed to restart after removing user. Rolling back ..."
            # Восстанавливаем строку пользователя
            modify_caddyfile "add" "$username" "$password" >/dev/null 2>&1
			restart_caddy true >/dev/null 2>&1
            read -rp "Press Enter to continue ..."
            continue
        fi
        
        # --- Удаляем данные пользователя ---
        sed -i "/^[[:space:]]*${id}[[:space:]]*|/d" /root/naive/registry.txt
        rm -rf "/root/naive/users/user_$(printf "%03d" "$id")_${username}"
        
        green "✓ User '$name' removed"
        echo ""
        read -rp "Press Enter to continue removing another user ..."
    done
    
    show_footer
}

# =====================================
# Function: Restart Caddy
# =====================================
restart_caddy() {
    local quiet=${1:-false}
    systemctl restart caddy 2>/dev/null
    sleep 2
    if systemctl is-active --quiet caddy; then
        return 0
    else
        if [[ "$quiet" != "true" ]]; then
            red "✗ Caddy failed to restart!"
            journalctl -u caddy -n 10 --no-pager
        fi
        return 1
    fi
}

# =====================================
# Function: Reboot server
# =====================================
reboot_server() {
    show_header
    
    yellow "○ This will reboot the server NOW"
    yellow "○ All running services will be stopped"
    yellow "○ You will be disconnected"
    echo ""
    read -rp "Are you sure you want to reboot? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        green "✓ Rebooting server ..."
        sleep 2
        reboot
    else
        yellow "○ Reboot cancelled"
        show_footer
    fi
}

# =====================================
# Function: Setup custom bash prompt (Kordan style)
# =====================================
setup_custom_prompt() {
    yellow "  Setting up custom bash prompt (Kordan style) ..."
    local ps1_new='\n\[\e[0;36m\]\t\[\e[0m\] \[\e[0;91m\]\u@\[\e[0m\]\[\e[0;33m\]\H:\[\e[0m\]\[\e[0;94m\][ \w ]\[\e[0;92m\]\n\\$ >> \[\e[0m\]'
    
    if ! grep -q "Kordan" /root/.bashrc 2>/dev/null; then
        echo "#Custom invitation from Kordan" >> /root/.bashrc
        echo "PS1='$ps1_new'" >> /root/.bashrc
        green "✓ Bash prompt updated (Kordan style) – visible after relogin"
    else
        yellow "○ Custom prompt already installed"
    fi
}

# =====================================
# Function: Main Menu
# =====================================
show_menu() {
    show_header
    
    detect_os_light
    green "     $OS_PRETTY_NAME"
	
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}    Proxy Management${PLAIN}"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}1.  Install${PLAIN}   NaiveProxy"
    echo -e " ${RED}2.  Uninstall${PLAIN} NaiveProxy"
	echo -e " ${YELLOW}3.  Recompile${PLAIN} NaiveProxy"
	
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}    User Management${PLAIN}"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
	echo -e " ${YELLOW}4.  Show${PLAIN}      users"
	echo -e " ${GREEN}5.  Add${PLAIN}       user"
	echo -e " ${RED}6.  Remove${PLAIN}    user"
	
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}    Server Management${PLAIN}"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}7.  Show${PLAIN}      system info"
    echo -e " ${GREEN}8.  Run${PLAIN}       system maintenance"
    echo -e " ${YELLOW}9.  Reboot${PLAIN}    server"	
	
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}    Certificate Management${PLAIN}"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}10. Backup${PLAIN}    certificate"
    echo -e " ${GREEN}11. Restore${PLAIN}   certificate"
    echo -e " ${GREEN}12. Check${PLAIN}     certificate"
        
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}0.  Exit${PLAIN}"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"   
    echo ""
    yellow "###############################################################"
    
    local attempts=0
    local max_attempts=3
    
    while true; do
        if [[ $attempts -ge $max_attempts ]]; then
            red "\nMaximum attempts $max_attempts exceeded. Exiting"
			sleep 1
            exit 1
        fi
		
        echo ""
        read -rp "  Your choice [0-12]: " answer
        
        if [[ -z "$answer" ]]; then
            attempts=$((attempts + 1))
            yellow "  Enter a number from 0 to 12. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if ! echo "$answer" | grep -qE '^[0-9]+$'; then
            attempts=$((attempts + 1))
            yellow "  Enter a number. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if [[ $answer -lt 0 ]] || [[ $answer -gt 12 ]]; then
            attempts=$((attempts + 1))
            yellow "  Number must be between 0 and 12. Attempt $attempts of $max_attempts"
            continue
        fi
        
        break
    done
    
    case $answer in
        # Proxy Management
        1) install_naiveproxy ;;
        2) uninstall_naiveproxy ;;
		3) check_and_update_naive ;;
		
		# User Management
        4) show_user_registry ;;
		5) add_new_user ;;
		6) remove_user ;;
        
        # Server Management
        7) show_system_info ;;
        8) system_maintenance ;;
        9) reboot_server ;;		
		
        # Certificate Management
        10) backup_certificates ;;
        11) restore_certificates ;;
        12) check_certificate_status ;;
                
        # Exit
        0) clear && exit 0 ;;
    esac
    
    if [[ $answer != "0" ]]; then
        echo ""
        read -rp "Press Enter to return to menu ... "
        show_menu
    fi
}

if [ "$1" == "--status" ]; then
    show_install_checklist
    exit 0
elif [ "$1" == "--list-users" ]; then
    show_user_registry
    exit 0
elif [ "$1" == "--add-user" ]; then
    add_new_user "$2"
    exit 0
elif [ "$1" == "--delete-user" ]; then
    remove_user "$2"
    exit 0
fi

# =====================================
# Start script
# =====================================
show_menu
