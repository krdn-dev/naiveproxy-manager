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
SSH_PORT=22
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
# Function: Install precompiled WebGhost binary
# =====================================
install_webghost() {
    yellow "Installing WebGhost (precompiled binary) ..."

    # Уже установлен?
    if [[ -f /usr/local/bin/webghost ]]; then
        green "✓ WebGhost already installed"
        return 0
    fi

    # 1. Попытка скопировать из локальной папки (рядом со скриптом)
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    if [[ -f "$script_dir/webghost" ]]; then
        cp "$script_dir/webghost" /usr/local/bin/webghost
        chmod +x /usr/local/bin/webghost
        green "✓ Installed WebGhost from local directory"
        return 0
    fi

    # 2. Попытка скачать из GitHub Releases
    local download_url="https://github.com/krdn-dev/naiveproxy-manager/releases/latest/download/webghost-linux-amd64"
    yellow "Downloading WebGhost from ${download_url} ..."
    curl -L --fail -o /usr/local/bin/webghost "$download_url" 2>/dev/null

    if [[ $? -ne 0 || ! -s /usr/local/bin/webghost ]]; then
        red "✗ Failed to download WebGhost"
        red "✗ Please place webghost binary in /usr/local/bin/ and rerun the installer"
        return 1
    fi

    chmod +x /usr/local/bin/webghost
    green "✓ WebGhost installed to /usr/local/bin/webghost"
}

# =====================================
# Function: Save runtime configuration
# =====================================
save_runtime_config() {
    mkdir -p /root/naive
    cat > /root/naive/runtime.env << EOF
# NaiveProxy Runtime Configuration - DO NOT EDIT MANUALLY
# Generated: $(date)
# WARNING: This file contains sensitive data! Keep it secure
proxyport='$proxyport'
proxyname='$proxyname'
proxypwd='$proxypwd'
domain='$domain'
email='$email'
SSH_PORT='$SSH_PORT'
REMOTE_SERVER='${REMOTE_SERVER:-}'
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
        source /root/naive/runtime.env
        return 0
    fi
    return 1
}

# =====================================
# Function: Backup certificates (complete Caddy data)
# =====================================
backup_certificates() {
    local backup_dir="/root/naive/cert-backup"
    
    mkdir -p "$backup_dir"
    
    # Загружаем конфигурацию, чтобы получить domain
    if [[ -f /root/naive/runtime.env ]]; then
        source /root/naive/runtime.env
    fi
    
    # Если domain все еще пустой, пробуем извлечь из сертификата
    if [[ -z "$domain" ]]; then
        local cert_file=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "*.crt" 2>/dev/null | head -1)
        if [[ -n "$cert_file" ]]; then
            domain=$(openssl x509 -subject -noout -in "$cert_file" 2>/dev/null | grep -oP 'CN=\K[^,]+')
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
    tar czf "$backup_file" -C "$(dirname "$caddy_data_dir")" "$(basename "$caddy_data_dir")" 2>/dev/null
	
	if [[ -s "$backup_file" ]]; then
		green "✓ Backup created ($(du -h "$backup_file" | cut -f1))"
	else
		red "✗ Backup file is empty – something went wrong"
		rm -f "$backup_file"
		return 1
	fi
    
    if [[ $? -eq 0 ]]; then
        cat > "$backup_dir/metadata.txt" << EOF
Domain: $domain
Backup date: $(date)
Caddy version: $(caddy version 2>/dev/null | head -1)
Backup path: $caddy_data_dir
Backup file: caddy_data_${domain}.tar.gz
EOF
        green "✓ Complete Caddy data backed up to: $backup_file"
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
    
    # Если не нашли по домену, ищем любой бэкап caddy_data_
    if [[ -z "$backup_file" ]]; then
        backup_file=$(ls -t "$backup_dir"/caddy_data_*.tar.gz 2>/dev/null | head -1)
    fi
    
    # Если все еще не нашли, ищем старый формат certs_
    if [[ -z "$backup_file" ]]; then
        backup_file=$(ls -t "$backup_dir"/certs_*.tar.gz 2>/dev/null | head -1)
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
        local backup_expiry=$(grep "Certificate expiry:" "$backup_dir/metadata.txt" 2>/dev/null | cut -d: -f2- | xargs)
        if [[ -n "$backup_expiry" ]]; then
            local expiry_epoch=$(date -d "$backup_expiry" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            
            if [[ $expiry_epoch -le $now_epoch ]]; then
                yellow "○ Backup certificate expired on $backup_expiry"
                return 1
            fi
            green "✓ Backup certificate valid until $backup_expiry"
        fi
    fi
    
    local temp_dir=$(mktemp -d)
	# Гарантированная очистка при выходе из функции
	trap "rm -rf $temp_dir" RETURN
    
    # Распаковываем во временную папку
    tar xzf "$backup_file" -C "$temp_dir" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        red "✗ Failed to extract backup"
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
    
    # Пробуем найти папку "caddy" в распакованном содержимом
    source_caddy_dir=$(find "$temp_dir" -type d -name "caddy" 2>/dev/null | head -1)
    
    # Если не нашли, пробуем найти папку "caddy-data" (старый формат с transform)
    if [[ -z "$source_caddy_dir" ]]; then
        source_caddy_dir=$(find "$temp_dir" -type d -name "caddy-data" 2>/dev/null | head -1)
    fi
    
    # Если нашли — копируем содержимое
    if [[ -n "$source_caddy_dir" ]] && [[ -d "$source_caddy_dir" ]]; then
        # Останавливаем Caddy перед восстановлением
        systemctl stop caddy 2>/dev/null
        
        # Удаляем старую папку
        rm -rf "$target_base/caddy"
        # Копируем новую
        cp -r "$source_caddy_dir" "$target_base/caddy"
        
        if [[ $? -eq 0 ]]; then
            green "✓ Caddy data restored from backup to: $target_base/caddy"
            
            # Проверяем, что сертификаты на месте
            local restored_cert=$(find "$target_base/caddy" -name "*.crt" 2>/dev/null | head -1)
            if [[ -n "$restored_cert" ]]; then
                green "✓ Certificate file found: $(basename "$restored_cert")"
                
                # Извлекаем домен из восстановленного сертификата
                local restored_domain=$(openssl x509 -subject -noout -in "$restored_cert" 2>/dev/null | grep -oP 'CN=\K[^,]+')
                if [[ -n "$restored_domain" ]]; then
                    green "✓ Certificate domain: $restored_domain"
                    # Обновляем domain в конфиге, если он был пустым
                    if [[ -z "$domain" ]] || [[ "$domain" != "$restored_domain" ]]; then
                        domain="$restored_domain"
                        save_runtime_config
                    fi
                fi
            fi
            
            # Запускаем Caddy заново
            systemctl start caddy 2>/dev/null
            sleep 3
            return 0
        else
            red "✗ Failed to copy restored data"
            systemctl start caddy 2>/dev/null
            return 1
        fi
    else
        # Пробуем старый формат (прямо certificates)
        local cert_dir=$(find "$temp_dir" -type d -name "certificates" 2>/dev/null | head -1)
        if [[ -n "$cert_dir" ]]; then
            systemctl stop caddy 2>/dev/null
            mkdir -p "$target_base/caddy"
            cp -r "$cert_dir" "$target_base/caddy/certificates"
            
            if [[ $? -eq 0 ]]; then
                green "✓ Certificates restored from backup (legacy format)"
                systemctl start caddy 2>/dev/null
                sleep 3
                return 0
            fi
            systemctl start caddy 2>/dev/null
        fi
    fi
    
    red "✗ Failed to restore: no valid Caddy data found in backup"
    yellow "  Backup contents:"
    tar tzf "$backup_file" 2>/dev/null | head -5 | sed 's/^/    /'
    return 1
}

# =====================================
# Function: Check backup contents
# =====================================
check_backup() {
    show_header
    
    local backup_dir="/root/naive/cert-backup"
    
    if [[ ! -d "$backup_dir" ]]; then
        yellow "○ No backup directory found"
        show_footer
        return 1
    fi
    
    echo ""
    yellow "Backup directory: $backup_dir"
    echo ""
    
    # Список бэкапов
    local backups=$(ls -la "$backup_dir"/*.tar.gz 2>/dev/null)
    if [[ -n "$backups" ]]; then
        yellow "Backup files:"
        echo "$backups" | sed 's/^/  /'
    else
        yellow "○ No backup files found"
    fi
    
    # Метаданные
    if [[ -f "$backup_dir/metadata.txt" ]]; then
        echo ""
        yellow "Metadata:"
        cat "$backup_dir/metadata.txt" | sed 's/^/  /'
    fi
    
    # Проверяем содержимое каждого бэкапа
    for backup in "$backup_dir"/*.tar.gz; do
        [[ -f "$backup" ]] || continue
        echo ""
        yellow "Contents of $(basename "$backup"):"
        tar tzf "$backup" 2>/dev/null | head -10 | sed 's/^/  /'
        local total=$(tar tzf "$backup" 2>/dev/null | wc -l)
        if [[ $total -gt 10 ]]; then
            echo "  ... and $((total - 10)) more files"
        fi
    done
    
    show_footer
}

# =====================================
# Function: Check certificate status and backup info
# =====================================
check_certificate_status() {
    show_header
    
    if ! is_naive_installed; then
        yellow "NaiveProxy is not installed!"
        show_footer
        return 0
    fi
    
    load_runtime_config
    
    if [[ -z "$domain" ]]; then
        red "✗ Domain not configured"
        show_footer
        return 1
    fi
    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                   Certificate Status"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    
    local cert_file=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    
    if [[ -n "$cert_file" ]] && [[ -f "$cert_file" ]]; then
        local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        local issuer=$(openssl x509 -issuer -noout -in "$cert_file" 2>/dev/null | sed 's/issuer=//')
        
        local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
        local now_epoch=$(date +%s)
        local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
        
        green "✓ Certificate found"
        echo -e "  ${GREEN}Domain:${PLAIN} $domain"
        echo -e "  ${GREEN}Issuer:${PLAIN} $issuer"
        echo -e "  ${GREEN}Expires:${PLAIN} $expiry_date"
        
        # Определяем CA по issuer (более точно)
        if [[ "$issuer" =~ "ZeroSSL" ]]; then
            echo -e "  ${GREEN}CA:${PLAIN} ZeroSSL (50 certs/week)"
        elif [[ "$issuer" =~ "Let's Encrypt" ]]; then
            echo -e "  ${GREEN}CA:${PLAIN} Let's Encrypt (5 certs/week)"
        fi
        
        if [[ $days_left -lt 0 ]]; then
            red "  Status: EXPIRED"
        elif [[ $days_left -lt 7 ]]; then
            yellow "  Status: Expires in $days_left days"
        else
            green "  Status: Valid ($days_left days remaining)"
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
            local error_desc=$(echo "$last_error" | grep -oP '"error":\s*"\K[^"]+' | tail -1)
            [[ -n "$error_desc" ]] && echo -e "  ${RED}Error:${PLAIN} $error_desc"
            
            # Извлекаем retry after (время снятия лимита)
            local retry_after
            retry_after=$(echo "$last_error" | grep -oP 'retry after \K[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')
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
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                   Let's Encrypt Limits"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Проверяем логи Caddy за последние 7 дней
    local rate_limit_count=$(journalctl -u caddy --since "7 days ago" 2>/dev/null | grep -ci "too many certificates")
    local cert_errors=$(journalctl -u caddy --since "7 days ago" 2>/dev/null | grep -ci "failed to obtain certificate")
    local remaining=$((5 - rate_limit_count))
    
    echo -e "${GREEN}Certificates issued (last 7 days):${PLAIN} $rate_limit_count/5"
    
    if [[ $rate_limit_count -ge 5 ]]; then
        red "  ✗ RATE LIMIT EXCEEDED!"
        # Вытаскиваем время снятия лимита из логов
        local retry_after_line
        retry_after_line=$(journalctl -u caddy --since "7 days ago" --no-pager 2>/dev/null | grep -oP 'retry after [0-9-]{10} [0-9:]{8}' | tail -1 | sed 's/retry after //')
        if [[ -n "$retry_after_line" ]]; then
            yellow "    ○ Rate limit reset at: $retry_after_line UTC"
        else
            yellow "    ○ No new certificates until next week"
        fi
        yellow "    ○ Use 'Restore' instead"
    elif [[ $rate_limit_count -ge 4 ]]; then
        yellow "  ○ WARNING: Only $remaining certificate(s) left this week"
    else
        green "  ✓ $remaining certificate(s) remaining this week"
    fi
    
    if [[ $cert_errors -gt 0 ]]; then
        yellow "  ○ Certificate failures (last 7 days): $cert_errors"
    fi
    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                   Backup Info"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    
    local backup_dir="/root/naive/cert-backup"
    local backup_file=""
    
    if [[ -f "$backup_dir/caddy_data_${domain}.tar.gz" ]]; then
        backup_file="$backup_dir/caddy_data_${domain}.tar.gz"
    elif [[ -f "$backup_dir/certs_${domain}.tar.gz" ]]; then
        backup_file="$backup_dir/certs_${domain}.tar.gz"
    fi
    
    if [[ -n "$backup_file" ]] && [[ -f "$backup_file" ]]; then
        green "✓ Backup exists"
        echo -e "  ${GREEN}File:${PLAIN} $(basename "$backup_file")"
        echo -e "  ${GREEN}Size:${PLAIN} $(du -h "$backup_file" | awk '{print $1}')"
        
        if [[ -f "$backup_dir/metadata.txt" ]]; then
            local backup_date=$(grep "Backup date:" "$backup_dir/metadata.txt" 2>/dev/null | cut -d: -f2- | xargs)
            local backup_expiry=$(grep "Certificate expiry:" "$backup_dir/metadata.txt" 2>/dev/null | cut -d: -f2- | xargs)
            local backup_path=$(grep "Backup path:" "$backup_dir/metadata.txt" 2>/dev/null | cut -d: -f2- | xargs)
            
            [[ -n "$backup_date" ]] && echo -e "  ${GREEN}Backup date:${PLAIN} $backup_date"
            [[ -n "$backup_expiry" ]] && echo -e "  ${GREEN}Certificate expiry:${PLAIN} $backup_expiry"
            [[ -n "$backup_path" ]] && echo -e "  ${GREEN}Source path:${PLAIN} $backup_path"
        fi
        
        # Показываем содержимое бэкапа
        echo ""
        yellow "  Backup content preview:"
        local file_list=$(tar tzf "$backup_file" 2>/dev/null | head -50)
        if [[ -n "$file_list" ]]; then
            echo "$file_list" | sed 's/^/    /'
            local total_files=$(tar tzf "$backup_file" 2>/dev/null | wc -l)
            if [[ $total_files -gt 50 ]]; then
                echo "    ... and $((total_files - 50)) more files"
            fi
        else
            yellow "    (empty or corrupt backup)"
        fi
    else
        yellow "○ No backup found"
        echo -e "  ${YELLOW}Tip:${PLAIN} Run option ${GREEN}13${PLAIN} to create a backup"
    fi
    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    
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
    if echo | openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | grep -q "notAfter="; then
        return 0
    fi
    
    # Fallback: проверяем только файл
    local cert_file=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    if [[ -z "$cert_file" ]] || [[ ! -f "$cert_file" ]]; then
        return 1
    fi
    
    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    local now_epoch=$(date +%s)
    
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
    local cert_info=$(echo | openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    
    if [[ -n "$cert_info" ]]; then
        # Сертификат работает и доступен через сеть
        local expiry_date=$(echo "$cert_info" | grep "notAfter=" | cut -d= -f2)
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
    local cert_file=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    
    if [[ -n "$cert_file" ]] && [[ -f "$cert_file" ]]; then
        # Проверяем, соответствует ли сертификат домену
        local cert_domain=$(openssl x509 -subject -noout -in "$cert_file" 2>/dev/null | grep -oP 'CN=\K[^,]+')
        if [[ -n "$cert_domain" ]] && [[ "$cert_domain" != "$domain" ]]; then
            echo "WRONG_DOMAIN:$cert_domain"
            return 2
        fi
        
        # Проверяем срок действия
        local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
        local now_epoch=$(date +%s)
        
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
# Function: Check and update NaiveProxy/Caddy
# =====================================
check_and_update_naive() {
    show_header
    
    # Получаем текущую версию
    local current_version=$(caddy version 2>/dev/null | awk '{print $1}')
    local latest_go_version=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
    
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
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Останавливаем сервис
        systemctl stop caddy
        
        # Переустанавливаем Go если нужно и пересобираем
        install_go
        build_caddy
        systemctl start caddy
        
        green "✓ NaiveProxy refreshed to latest forwardproxy version"
    fi
}

# =====================================
# Function: Setup auto-update cron (inlined in install)
# =====================================
setup_auto_update_cron() {
    # Создаем скрипт обновления
    cat > /usr/local/bin/naive-update << 'EOF'
#!/bin/bash
LOG="/var/log/naive-update.log"
echo "[$(date)] Checking NaiveProxy update ..." >> "$LOG"

# Проверяем, когда последний раз собирали Caddy
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

# Останавливаем
systemctl stop caddy

# Пересобираем
export PATH=$PATH:/usr/local/go/bin
cd /root
rm -rf /root/tmp
mkdir -p /root/tmp
export TMPDIR=/root/tmp

export GOBIN=/root/go/bin
export PATH=$PATH:/usr/local/go/bin:$GOBIN
if ! command -v xcaddy &>/dev/null; then
    echo "[$(date)] xcaddy not found, attempting to install..." >> "$LOG"
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
fi

xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive --with github.com/mholt/caddy-ratelimit >> "$LOG" 2>&1

if [[ -f ./caddy ]]; then
    mv ./caddy /usr/bin/caddy
    chmod +x /usr/bin/caddy
    systemctl start caddy
    echo "[$(date)] Caddy rebuilt successfully" >> "$LOG"
else
    echo "[$(date)] Build failed!" >> "$LOG"
    systemctl start caddy
fi
EOF

    chmod +x /usr/local/bin/naive-update
    
    # Добавляем в crontab (если еще нет)
    if ! crontab -l 2>/dev/null | grep -q "naive-update"; then
        (crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/local/bin/naive-update") | crontab -
        green "✓ Auto-update cron installed (weekly, Sunday 3:00 AM)"
    fi
	
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
    green "✓ Log rotation configured (monthly, keep 12 months)"
}

# =====================================
# Function: Show system information
# =====================================
show_system_info() {
    show_header
    
    echo -e "${GREEN}Operating System:${PLAIN} $SYSTEM $VERSION"
    echo -e "${GREEN}Architecture:${PLAIN} $(uname -m)"
    echo -e "${GREEN}Kernel:${PLAIN} $(uname -r)"
    echo -e "${GREEN}Uptime:${PLAIN} $(uptime -p | sed 's/up //')"
    echo -e "${GREEN}CPU:${PLAIN} $(nproc) cores"
    
    TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
    USED_RAM=$(free -h | awk '/^Mem:/ {print $3}')
    FREE_RAM=$(free -h | awk '/^Mem:/ {print $4}')
    RAM_PERCENT=$(free | awk '/^Mem:/ {printf "%.1f%%", $3/$2 * 100.0}')
    echo -e "${GREEN}RAM:${PLAIN} Total: $TOTAL_RAM, Used: $USED_RAM, Free: $FREE_RAM ($RAM_PERCENT)"
    
    if swapon --show 2>/dev/null | grep -q "/swapfile"; then
        SWAP_SIZE=$(swapon --show --bytes | awk '/swapfile/ {print $3}' | numfmt --to=iec 2>/dev/null || echo "unknown")
        echo -e "${GREEN}Swap:${PLAIN} $SWAP_SIZE (active)"
    else
        echo -e "${GREEN}Swap:${PLAIN} not configured"
    fi
    
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
    DISK_PERCENT=$(df / | awk 'NR==2 {print $5}')
    echo -e "${GREEN}Disk (/):${PLAIN} Total: $DISK_TOTAL, Used: $DISK_USED, Free: $DISK_FREE ($DISK_PERCENT)"
    
    SERVER_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "unknown")
    echo -e "${GREEN}External IP:${PLAIN} $SERVER_IP"
    
    CONNS=$(ss -t state established | wc -l)
    echo -e "${GREEN}Active connections:${PLAIN} $CONNS"
    
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
    
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        echo -e "${GREEN}TCP congestion:${PLAIN} BBR"
    else
        echo -e "${GREEN}TCP congestion:${PLAIN} $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'unknown')"
    fi
	
    echo -e "${GREEN}Bash:${PLAIN} ${BASH_VERSION}"
   
    if command -v openssl &>/dev/null; then
        SSL_VERSION=$(openssl version | awk '{print $1, $2}')
        echo -e "${GREEN}OpenSSL:${PLAIN} $SSL_VERSION"
    fi
    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                   NaiveProxy Status"
    yellow "═══════════════════════════════════════════════════════════════"
    
    if ! is_naive_installed; then
        echo ""
        red "✗ NaiveProxy is NOT installed"
        show_footer
        return 0
    fi
    
    if [[ -f /root/naive/runtime.env ]]; then
        source /root/naive/runtime.env
        green "✓ Configuration loaded"
    else
        red "✗ Configuration file not found"
        show_footer
        return 1
    fi
    
    [[ -z "$domain" ]] && red "✗ Domain: missing" || green "✓ Domain: $domain"
    [[ -z "$proxyport" ]] && red "✗ Proxy port: missing" || green "✓ Proxy port: $proxyport"
    [[ -z "$proxyname" ]] && red "✗ Username: missing" || green "✓ Username: $proxyname"
    [[ -z "$proxypwd" ]] && red "✗ Password: missing" || green "✓ Password: [set]"
    
    # РЕАЛЬНАЯ ПРОВЕРКА СЕРТИФИКАТА
    local cert_status=$(check_certificate_working "$domain")
    
    case $cert_status in
        WORKING:*)
            local expiry_date="${cert_status#WORKING:}"
            green "✓ SSL certificate: WORKING and accessible"
            echo -e "  ${GREEN}Expires:${PLAIN} $expiry_date"
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
		echo -e "${GREEN}  Caddy version:${PLAIN} $CADDY_VER"
	fi
    
    if command -v go &>/dev/null; then
		GO_VER=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//')
		echo -e "${GREEN}  Go version:${PLAIN} $GO_VER"
	fi

    if systemctl is-active --quiet caddy 2>/dev/null; then
        green "✓ Caddy service: running"
    else
        red "✗ Caddy service: NOT running"
    fi
	
    if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban 2>/dev/null; then
        JAILED=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print $4}' || echo "0")
        green "✓ fail2ban: running (banned: $JAILED IPs)"
    else
        yellow "○ fail2ban: not running"
    fi
    
    echo -e "${YELLOW}Public ports (accessible from internet):${PLAIN}"
    PUBLIC_PORTS=$(ss -tlnp 2>/dev/null | grep -v "127.0.0.1" | grep -v "::1" | awk '{print $4}' | grep -oE ':[0-9]+$' | sort -u | sed 's/://')
    if [[ -n "$PUBLIC_PORTS" ]]; then
        echo "$PUBLIC_PORTS" | sed 's/^/  /'
    else
        echo "  none"
    fi
	
    echo ""
	
    if [[ "$SERVER_IP" != "unknown" ]]; then
        if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/443" 2>/dev/null; then
            green "✓ Port 443: reachable from internet"
        else
            red "✗ Port 443: NOT reachable from internet"
            yellow "  ○ Check firewall and NAT settings"
        fi
    else
        yellow "○ Could not determine external IP"
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
    
    echo "System maintenance options:"
    echo ""
    echo "  1. Update package lists"
    echo "  2. Upgrade all packages"
    echo "  3. Clean up unused packages"
    echo "  4. Full maintenance (all of the above)"
    echo "  0. Cancel"
    echo ""
    
    read -rp "Your choice [0-4]: " maint_choice
    
    case $maint_choice in
        0)
            green "Maintenance cancelled"
            show_footer
            return 0
            ;;
        1)
            echo ""
            update_package_lists
            ;;
        2)
            echo ""
            upgrade_all_packages
            ;;
        3)
            echo ""
            cleanup_unused_packages
            ;;
        4)
            echo ""
            yellow "Running full maintenance ..."
            update_package_lists
            upgrade_all_packages
            cleanup_unused_packages
            ;;
        *)
            red "Invalid choice"
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
    yellow "Setting up NaiveGuard pro-active watchdog for self-healing..."

    cat > /usr/local/bin/naiveguard.sh << 'SCRIPT_EOF'
#!/bin/bash
LOG="/var/log/naiveguard.log"

# ===== Проверка 1: Работа Caddy =====
if ! systemctl is-active --quiet caddy; then
    echo "[$(date)] Caddy is down, restarting..." >> "$LOG"
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
        echo "[$(date)] Caddy binary is $DAYS_SINCE_BUILD days old. Auto-rebuilding..." >> "$LOG"
        if command -v xcaddy &>/dev/null; then
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
                echo "[$(date)] Auto-rebuild SUCCESS." >> "$LOG"
            else
                systemctl start caddy
                echo "[$(date)] Auto-rebuild FAILED." >> "$LOG"
            fi
        else
            echo "[$(date)] xcaddy not found, cannot auto-rebuild." >> "$LOG"
        fi
    fi
fi

# ===== Проверка 3: Сертификат и лимиты =====
if [[ -f /root/naive/runtime.env ]]; then
    source /root/naive/runtime.env

    # Если сертификат не найден, пробуем восстановить из бэкапа
    CERT_FILE=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    if [[ -z "$CERT_FILE" ]]; then
        echo "[$(date)] Certificate not found. Attempting restore from backup..." >> "$LOG"
        BACKUP_FILE=$(ls -t /root/naive/cert-backup/caddy_data_*.tar.gz 2>/dev/null | head -1)
        if [[ -n "$BACKUP_FILE" ]]; then
            tar xzf "$BACKUP_FILE" -C /tmp/ 2>/dev/null
            # Ищем папку caddy внутри архива
            SRC=$(find /tmp/ -type d -name "caddy" | head -1)
            if [[ -n "$SRC" ]]; then
                TARGET="/root/.local/share"
                mkdir -p "$TARGET"
                rm -rf "$TARGET/caddy"
                cp -r "$SRC" "$TARGET/caddy"
                systemctl restart caddy
                echo "[$(date)] Certificate restored from backup." >> "$LOG"
            fi
            rm -rf /tmp/*
        else
            # Проверяем, не прошло ли время retry after для Let's Encrypt
            RETRY_LOG=$(journalctl -u caddy --since "1 hour ago" | grep -oP 'retry after \K[0-9-]+ [0-9:]+')
            if [[ -n "$RETRY_LOG" ]]; then
                RETRY_EPOCH=$(date -d "$RETRY_LOG" +%s)
                NOW_EPOCH=$(date +%s)
                if [[ $NOW_EPOCH -gt $RETRY_EPOCH ]]; then
                    echo "[$(date)] Rate limit window passed, restarting Caddy to obtain certificate..." >> "$LOG"
                    systemctl restart caddy
                else
                    echo "[$(date)] Rate limit still active until $RETRY_LOG, waiting." >> "$LOG"
                fi
            fi
        fi
    fi
fi

# ===== Проверка 4: Свободное место =====
USED=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $USED -gt 90 ]]; then
    echo "[$(date)] Disk usage >90%, cleaning temp files and old Caddy build caches..." >> "$LOG"
    rm -rf /root/tmp/*
    rm -rf /root/.cache/go-build
    docker system prune -af 2>/dev/null
    journalctl --vacuum-size=100M
fi

# ===== Проверка 5: fail2ban =====
if command -v fail2ban-client &>/dev/null; then
    if ! systemctl is-active --quiet fail2ban; then
        echo "[$(date)] fail2ban not running, restarting..." >> "$LOG"
        systemctl restart fail2ban
    fi
fi

echo "[$(date)] NaiveGuard check completed." >> "$LOG"
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
    systemctl enable --now naiveguard.timer
	
	# Создаём лог-файл заранее
    touch /var/log/naiveguard.log
    chmod 644 /var/log/naiveguard.log
	
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
# Function: Check system requirements (enhanced)
# =====================================
check_system_requirements() {
    if [[ $EUID -ne 0 ]]; then
        red "ATTENTION: Run the script as root user"
        exit 1
    fi

    # Проверка занятости apt/dpkg
    if command -v dpkg &>/dev/null; then
        if pgrep -x "apt" > /dev/null || pgrep -x "dpkg" > /dev/null || pgrep -x "apt-get" > /dev/null; then
            red "Another apt/dpkg process is running. Wait or kill it."
            exit 1
        fi
    fi

    # Проверка интернета
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        red "No internet access (cannot ping 8.8.8.8)"
        exit 1
    fi

    # Проверка DNS
    if ! nslookup google.com &>/dev/null && ! host google.com &>/dev/null; then
        yellow "Warning: DNS resolution problem (may affect certificate issuance)"
    fi

    # Проверка свободного места (минимум 2 ГБ)
    local free_gb=$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
    if [[ ${free_gb} -lt 2 ]]; then
        red "Not enough free disk space (need ≥2 GB, have ${free_gb}G)"
        exit 1
    fi

    # Проверка обязательных утилит
    for cmd in systemctl grep awk curl; do
        if ! command -v "$cmd" &>/dev/null; then
            red "Required command '$cmd' not found. Install it first."
            exit 1
        fi
    done

    # Определение ОС (уже существующий код)
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
    
    # Проверка версии (уже существующий код)
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
    
    green "     $SYSTEM $VERSION"
}

# =====================================
# Function: Configure automatic updates based on OS
# =====================================
setup_auto_updates() {
    yellow "Setting up automatic security updates ..."
    
    case $SYSTEM in
        "Debian"|"Ubuntu")
            if ! dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed"; then
                ${PACKAGE_INSTALL[int]} unattended-upgrades -y 2>/dev/null
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
            green "Unattended upgrades are enabled"
            ;;
        "CentOS"|"Fedora"|"AlmaLinux"|"Rocky Linux"|"Oracle Linux")
            ${PACKAGE_INSTALL[int]} dnf-automatic -y 2>/dev/null
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
# Function: Setting up fail2ban
# =====================================
setup_fail2ban() {
    yellow "Configuring fail2ban to protect SSH (port: $SSH_PORT) ..."
    
    if ! command -v fail2ban-client &>/dev/null; then
        ${PACKAGE_INSTALL[int]} fail2ban -y 2>/dev/null
    fi
    
    if ! command -v fail2ban-client &>/dev/null; then
        yellow "fail2ban is not installed (skip)"
        return 0
    fi
    
    mkdir -p /etc/fail2ban
    
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/secure
EOF

    if [[ $SYSTEM == "Debian" ]] || [[ $SYSTEM == "Ubuntu" ]]; then
        sed -i 's|/var/log/secure|/var/log/auth.log|' /etc/fail2ban/jail.local
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
    case "$(uname -m)" in
        x86_64|amd64) green "Architecture: x86_64" ;;
        aarch64|arm64) green "Architecture: ARM64" ;;
        *) red "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac
    
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    
    if [[ $TOTAL_RAM_MB -lt 1024 ]]; then
        if [[ $TOTAL_RAM_MB -lt 256 ]]; then
            red "Not enough RAM: ${TOTAL_RAM_MB}MB (minimum 256MB required)"
            exit 1
        elif [[ $TOTAL_RAM_MB -lt 512 ]]; then
            yellow "RAM ${TOTAL_RAM_MB}MB may not be enough to compile Caddy"
        else
            green "RAM: ${TOTAL_RAM_MB}MB"
        fi
    else
        TOTAL_RAM_GB=$(echo "scale=1; $TOTAL_RAM_MB / 1024" | bc)
        green "RAM: ${TOTAL_RAM_GB}GB"
    fi
    
    FREE_SPACE_MB=$(df -m / | awk 'NR==2 {print $4}')
    FREE_SPACE_GB=$(echo "scale=1; $FREE_SPACE_MB / 1024" | bc)
    
    if [[ $FREE_SPACE_MB -lt 1024 ]]; then
        red "Not enough free space: ${FREE_SPACE_MB}MB (minimum required 1GB)"
        exit 1
    else
        green "Free space: ${FREE_SPACE_GB}GB"
    fi
}

# =====================================
# Function: Create swap file if low memory
# =====================================
setup_swap() {
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    
    if [[ $TOTAL_RAM -ge 4096 ]]; then
        green "RAM: ${TOTAL_RAM}MB, swap not required"
        return 0
    fi
    
    if swapon --show | grep -q "/swapfile"; then
        green "Swap already configured"
        return 0
    fi
    
    if [[ $TOTAL_RAM -lt 512 ]]; then
        SWAP_SIZE=2
    elif [[ $TOTAL_RAM -lt 1024 ]]; then
        SWAP_SIZE=1.5
    elif [[ $TOTAL_RAM -lt 2048 ]]; then
        SWAP_SIZE=1
    elif [[ $TOTAL_RAM -lt 4096 ]]; then
        SWAP_SIZE=2
    else
        SWAP_SIZE=2
    fi
    
    yellow "Low memory detected (${TOTAL_RAM}MB). Creating ${SWAP_SIZE}GB swap file ..."
    
    if [[ "$SWAP_SIZE" == "1.5" ]]; then
        SWAP_MB=1536
    else
        SWAP_MB=$((SWAP_SIZE * 1024))
    fi
    
    swapoff /swapfile 2>/dev/null || true
    rm -f /swapfile 2>/dev/null || true
    
    if fallocate -l ${SWAP_MB}M /swapfile 2>/dev/null; then
        chmod 600 /swapfile
        mkswap /swapfile 2>/dev/null
        swapon /swapfile 2>/dev/null
        
        if ! grep -q "^/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        fi
        
        green "Swap file created (${SWAP_SIZE}GB / ${SWAP_MB}MB)"
    else
        yellow "fallocate failed, using dd (may take a moment) ..."
        dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_MB status=progress 2>/dev/null
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
    
    if [[ $SYSTEM == "CentOS" ]] && [[ ${VERSION:-0} -ge 8 ]]; then
        ${PACKAGE_UPDATE[int]} 2>/dev/null || true
    elif [[ $SYSTEM != "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    
    if [[ $SYSTEM == "CentOS" ]] || [[ $SYSTEM == "Fedora" ]] || [[ $SYSTEM == "AlmaLinux" ]] || [[ $SYSTEM == "Rocky Linux" ]]; then
        if ! rpm -q epel-release &>/dev/null && ! rpm -q epel-next-release &>/dev/null; then
            yellow "Connecting the EPEL repository ..."
            ${PACKAGE_INSTALL[int]} epel-release -y 2>/dev/null
        fi
    fi
    
    if [[ $SYSTEM == "Oracle Linux" ]]; then
        if ! dnf repolist | grep -q "ol10_developer_EPEL"; then
            yellow "Connecting Oracle Linux EPEL repository ..."
            ${PACKAGE_INSTALL[int]} oracle-epel-release-el10 -y 2>/dev/null
        fi
    fi
    
    ${PACKAGE_INSTALL[int]} curl wget git
    
    if ! command -v bc &>/dev/null; then
        yellow "Installing bc (calculator) ..."
        ${PACKAGE_INSTALL[int]} bc -y 2>/dev/null
    fi
    
    if ! command -v dig &>/dev/null; then
        yellow "Installation dnsutils (dig) ..."
        ${PACKAGE_INSTALL[int]} dnsutils 2>/dev/null || ${PACKAGE_INSTALL[int]} bind-utils 2>/dev/null
    fi
    
    if [[ $SYSTEM == "Debian" ]] || [[ $SYSTEM == "Ubuntu" ]]; then
        ${PACKAGE_INSTALL[int]} build-essential
    else
        ${PACKAGE_INSTALL[int]} gcc gcc-c++ make
    fi
    
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
    yellow "Configuring firewall (SSH port: $SSH_PORT) ..."
    
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
            ufw allow 443/udp 2>/dev/null   # ← Добавить для QUIC
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
            firewall-cmd --permanent --add-port=443/udp 2>/dev/null   # ← Добавить
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
    CURRENT_SSH_PORT=$(ss -tlnp | grep -oP '(?<=:)\d+(?=.*sshd)' | head -n1)
    [[ -z "$CURRENT_SSH_PORT" ]] && CURRENT_SSH_PORT=22
    
    if [[ $SSH_PORT -eq $CURRENT_SSH_PORT ]]; then
        yellow "○ SSH port already set to $SSH_PORT (no changes needed)"
        return 0
    fi
    
    yellow "Changing SSH port from $CURRENT_SSH_PORT to $SSH_PORT ..."
    
    sed -i "s/^#Port $CURRENT_SSH_PORT/Port $SSH_PORT/" /etc/ssh/sshd_config
    sed -i "s/^Port $CURRENT_SSH_PORT/Port $SSH_PORT/" /etc/ssh/sshd_config
    
    if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
        echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
    fi
    
    if sshd -t; then
        systemctl restart sshd
        green "✓ SSH port changed from $CURRENT_SSH_PORT to $SSH_PORT"
        echo ""
        yellow "○ Current session remains active on port $CURRENT_SSH_PORT"
        if [[ "$SERVER_IP" != "unknown" ]]; then
			yellow "○ Next time connect using: ssh -p $SSH_PORT root@$SERVER_IP"
		else
			yellow "○ Next time connect using: ssh -p $SSH_PORT root@<your-server-ip>"
		fi
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

    # Проверяем, не используется ли Go другими проектами
    if [[ -d /usr/local/go ]]; then
        yellow "○ Go already installed at /usr/local/go"
        if command -v go &>/dev/null; then
            local installed_go=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//')
            green "  Current version: $installed_go"
        fi
        read -rp "Overwrite existing Go installation? [y/N]: " overwrite_go
        if [[ ! "$overwrite_go" =~ ^[Yy]$ ]]; then
            green "✓ Keeping existing Go installation"
            return 0
        fi
    fi
    rm -rf /usr/local/go

    for i in 1 2 3; do
        yellow "Downloading $LATEST_GO_VERSION for linux/$ARCH (attempt $i)..."
        wget -q --show-progress "$DOWNLOAD_URL" -O /tmp/go.tar.gz && break
        sleep 3
    done

    if [[ ! -s /tmp/go.tar.gz ]]; then
        red "Error downloading Go after 3 attempts. Please check your connection"
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
# Function: User input parameters
# =====================================
input_parameters() {
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                      Configuration Wizard"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    
		if [[ -f /root/naive/runtime.env ]]; then
			source /root/naive/runtime.env
			green "○ Found existing configuration for domain: $domain"
			echo ""
			
			while true; do
				read -rp "Do you want to use these settings? [Y/n]: " use_saved
				
				# Приводим к нижнему регистру и убираем пробелы
				use_saved=$(echo "$use_saved" | tr '[:upper:]' '[:lower:]' | xargs)
				
				case $use_saved in
					n|no)
						yellow "○ OK, let's reconfigure everything"
						unset SSH_PORT proxyport domain email proxyname proxypwd
						break
						;;
					""|y|yes)
						green "✓ Using saved configuration"
						green "  Domain: $domain"
						green "  Proxy port: $proxyport"
						green "  SSH port: $SSH_PORT"
						green "  Username: $proxyname"
						green "  Password: $proxypwd"
						echo ""
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
                while true; do
                    read -rp "$(yellow "Enter custom SSH port (1024-65535): ")" ssh_port_input
                    if [[ "$ssh_port_input" =~ ^[0-9]+$ ]] && [ "$ssh_port_input" -ge 1024 ] && [ "$ssh_port_input" -le 65535 ]; then
                        SSH_PORT="$ssh_port_input"
                        green "✓ SSH port set to: $SSH_PORT"
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
                if ss -tlnp | grep -q ":$proxyport "; then
                    red "✗ Port $proxyport is already in use by another process!"
                    yellow "Please select another port:"
                    continue
                fi
                green "✓ Port $proxyport selected and available"
                break
                ;;
            2)
                proxyport=8443
                if ss -tlnp | grep -q ":$proxyport "; then
                    red "✗ Port $proxyport is already in use by another process!"
                    yellow "Please select another port:"
                    continue
                fi
                green "✓ Port $proxyport selected and available"
                break
                ;;
            3)
                while true; do
                    read -rp "$(yellow "Enter custom port (1024-65535): ")" proxyport
                    if [[ ! "$proxyport" =~ ^[0-9]+$ ]] || [ "$proxyport" -lt 1024 ] || [ "$proxyport" -gt 65535 ]; then
                        red "✗ Error: Invalid port — must be number between 1024 and 65535"
                        continue
                    fi
                    
                    if ss -tlnp | grep -q ":$proxyport "; then
                        red "✗ Port $proxyport is already in use by another process!"
                        yellow "Please select another port:"
                        continue
                    fi
                    
                    green "✓ Port $proxyport selected and available"
                    break 2
                done
                ;;
            *)
                red "✗ Invalid choice — please select 1, 2, or 3"
                continue
                ;;
        esac
    done

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
        
        yellow "→ Checking DNS ..."
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

    echo ""
    read -rp "$(blue "→ Enter remote server for mutual traffic imitation (IP or domain, leave empty to skip): ")" remote_server_input
    
    if [[ -n "$remote_server_input" ]]; then
        # Простая валидация: IP или домен
        if [[ "$remote_server_input" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
           [[ "$remote_server_input" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
            REMOTE_SERVER="$remote_server_input"
            green "✓ Remote server set: $REMOTE_SERVER"
        else
            yellow "○ Invalid format, mutual imitation disabled"
            REMOTE_SERVER=""
        fi
    else
        REMOTE_SERVER=""
    fi

    # ----- Генерируем admin credentials -----
		proxyname=$(openssl rand -hex 12)
		proxypwd=$(openssl rand -hex 16)
		green "✓ Admin credentials generated"
	
	    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                  Review Your Settings"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    green "  SSH port:      $SSH_PORT"
    green "  Proxy port:    $proxyport"
    green "  Domain:        $domain"
    green "  Email:         $email"
    green "  Username:      $proxyname"
    green "  Password:      $proxypwd"
    echo ""
    
    while true; do
        read -rp "Do you want to proceed with these settings? [Y/n]: " confirm
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

# =====================================
# Function: Build Caddy
# =====================================
build_caddy() {
    export GOBIN=/root/go/bin
    export PATH=$PATH:/usr/local/go/bin:$GOBIN

    # Создаём временную директорию заранее (нужна и для go install, и для xcaddy)
    mkdir -p /root/tmp
    export TMPDIR=/root/tmp

    # Устанавливаем xcaddy, если его ещё нет
    if ! command -v xcaddy &>/dev/null; then
        yellow "Installing xcaddy..."
        for i in 1 2 3; do
            go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest && break
            sleep 3
        done
        if ! command -v xcaddy &>/dev/null; then
            red "Failed to install xcaddy after 3 attempts. Check Go environment and internet."
            return 1
        fi
    fi

    yellow "Building Caddy with the forwardproxy plugin (may take 3-5 minutes) ..."
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
        green "✓ Caddy build successful"
    else
        red "✗ Caddy build failed! ./caddy not found."
        return 1
    fi
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
    
    servers {
        protocols h1 h2 h3
		
        listener_wrappers {
            ja3
            tls
        }
    }
}

:${proxyport}, ${domain}:${proxyport} {
    ja3
    encode br zstd deflate gzip

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
	
    # Устанавливаем безопасные права на конфигурацию
    chmod 600 /root/naive/naive-client.json
    chmod 600 /root/naive/naive-url.txt
}

# =====================================
# Function: Create a systemd service
# =====================================
create_systemd_service() {
    pkill -x caddy 2>/dev/null
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
    sleep 2
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
    yellow "Disabling unnecessary services for security ..."
    
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
    yellow "Applying sysctl optimizations for proxy ..."
    
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
    yellow "Increasing system limits for high-load performance ..."
    
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
# Function: Wait for SSL certificate (with backup fallback)
# =====================================
wait_for_ssl_certificate() {
    local domain=$1
    local max_wait=70
    local waited=0

    # Пробуем восстановить из бэкапа (быстро)
    if restore_certificates "true"; then          # silent mode
        green "✓ Certificates restored from backup"
        systemctl restart caddy
        sleep 5
        if ! systemctl is-active --quiet caddy; then
            red "✗ Caddy failed to restart after restore"
            return 1
        fi
        # Проверяем доступность порта с коротким таймаутом
        if timeout 2 bash -c "echo >/dev/tcp/$domain/443" 2>/dev/null; then
            green "✓ Restored certificate is working"
            return 0
        fi
    fi

    echo ""
    yellow "○ Waiting for SSL certificate to become accessible ..."
    echo ""

    while [[ $waited -lt $max_wait ]]; do
        # Ранний выход при критических ошибках в логах Caddy
        local recent_errors=$(journalctl -u caddy --since "60 seconds ago" --no-pager 2>/dev/null | grep -i "rateLimited\|rejectedIdentifier\|too many certificates\|identifier is disallowed")
        if [[ -n "$recent_errors" ]]; then
            # Игнорируем rejectedIdentifier, если он относится к ZeroSSL
            if echo "$recent_errors" | grep -qi "rejectedIdentifier" && echo "$recent_errors" | grep -qi "zerossl"; then
                # Только ZeroSSL отклонил – не прерываем ожидание
                :
            else
                # Критическая ошибка (Let's Encrypt rate limit или реальный rejected)
                echo ""
                red "✗ Certificate issuance blocked (rate limit or domain rejected)"
                # Извлекаем время снятия лимита
                local retry_after
                retry_after=$(echo "$recent_errors" | grep -oP 'retry after \K[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | tail -1)
                if [[ -n "$retry_after" ]]; then
                    yellow "○ Let's Encrypt rate limit resets at: $retry_after UTC"
                    yellow "○ You can restart Caddy after this time to obtain the certificate (menu option 6)"
                fi
                journalctl -u caddy --since "60 seconds ago" --no-pager | grep -i "error\|rateLimit\|rejected" | tail -5
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
# Function: Create website structure via WebGhost
# =====================================
create_landing_page() {
    yellow "Creating complete website structure for ${domain} via WebGhost ..."

    # Явная проверка, что domain не пуст
    if [[ -z "${domain}" ]]; then
        red "✗ Domain variable is empty – cannot create landing page"
        return 1
    fi

    /usr/local/bin/webghost --domain="$domain" setup-site
    if [[ $? -ne 0 ]]; then
        red "✗ WebGhost setup-site failed"
        return 1
    fi

    green "✓ Website structure created for domain ${domain}"
}

# =====================================
# Function: Setup traffic imitation via WebGhost
# =====================================
setup_random_activity() {
    # Скрипт-обёртка для systemd
    cat > /usr/local/bin/webghost-activity.sh << WEOF
#!/bin/bash
source /root/naive/runtime.env
exec /usr/local/bin/webghost \
    --domain="${domain}" \
    --remote="${REMOTE_SERVER:-}" \
    --log=/var/log/website-activity.log \
    simulate
WEOF
    chmod +x /usr/local/bin/webghost-activity.sh

    # Systemd service
    cat > /etc/systemd/system/webghost-activity.service << EOF
[Unit]
Description=WebGhost traffic simulation
After=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/webghost-activity.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=2400
EOF

    # Systemd timer (каждые 45 минут днём, каждые 2 часа ночью)
    cat > /etc/systemd/system/webghost-activity.timer << EOF
[Unit]
Description=WebGhost activity timer
Requires=webghost-activity.service

[Timer]
OnCalendar=*:0/45
OnCalendar=*-*-* 23..05:0/120
RandomizedDelaySec=1200
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable webghost-activity.timer
    systemctl restart webghost-activity.timer

    # Лог-ротация
    cat > /etc/logrotate.d/website-activity << EOF
/var/log/website-activity.log {
    monthly
    rotate 12
    compress
    missingok
    notifempty
    create 644 root root
    postrotate
        systemctl restart webghost-activity.timer 2>/dev/null || true
    endscript
}
EOF

    # Пробный запуск в фоне для проверки
    /usr/local/bin/webghost-activity.sh &

    echo ""
    green "✓ WebGhost traffic simulation installed!"
    echo "  Timer: every 45 min (day) / 2 hours (night)"
    echo "  Log:   tail -f /var/log/website-activity.log"
}


# =====================================
# Function: Show installation checklist
# =====================================
show_install_checklist() {
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                    Installation Checklist"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""

    # Caddy service
    if systemctl is-active --quiet caddy; then
        green "✓ Caddy service: running"
    else
        red "✗ Caddy service: NOT running"
    fi

    # Ports
    ss -tlnp | grep -q ":$SSH_PORT " && green "✓ Port $SSH_PORT (SSH): listening" || yellow "○ Port $SSH_PORT (SSH): not listening"
    ss -tlnp | grep -q ":80 " && green "✓ Port 80: listening" || green "○ Port 80: not listening"
    ss -tlnp | grep -q ":443 " && green "✓ Port 443: listening" || green "○ Port 443: not listening"

    # Firewall
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
                firewall-cmd --list-ports 2>/dev/null | grep -q "$SSH_PORT/tcp" && green "✓ firewalld: port $SSH_PORT (SSH) allowed" || yellow "○ firewalld: port $SSH_PORT (SSH) not allowed"
                firewall-cmd --list-ports 2>/dev/null | grep -q "80/tcp" && green "✓ firewalld: port 80 allowed" || yellow "○ firewalld: port 80 not allowed"
                firewall-cmd --list-ports 2>/dev/null | grep -q "443/tcp" && green "✓ firewalld: port 443 allowed" || yellow "○ firewalld: port 443 not allowed"
            else
                yellow "○ firewalld: not active"
            fi
            ;;
        *)
            yellow "○ Firewall: unknown system"
            ;;
    esac

    # SSL certificate
    local cert_file=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    if [[ -n "$cert_file" ]]; then
        local cert_expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        green "✓ SSL certificate: valid until ${cert_expiry}"
        # Days left
        local expiry_epoch=$(date -d "$cert_expiry" +%s 2>/dev/null)
        local now_epoch=$(date +%s)
        local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
        if [[ $days_left -lt 7 ]]; then
            yellow "○ Certificate expires in ${days_left} days"
        fi
    else
        red "✗ SSL certificate: not obtained"
    fi

    # Client config
    [[ -f /root/naive/naive-client.json ]] && green "✓ Client config: /root/naive/naive-client.json" || red "✗ Client config: missing"
    [[ -f /root/naive/naive-url.txt ]] && green "✓ Import link: /root/naive/naive-url.txt" || red "✗ Import link: missing"

    # fail2ban
    if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban; then
        local banned=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print $4}')
        green "✓ fail2ban: active (banned: ${banned:-0})"
    else
        yellow "○ fail2ban: not active"
    fi

    # BBR
    sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr" && green "✓ BBR: enabled" || yellow "○ BBR: not enabled"

    # Watchdog (NaiveGuard)
    if systemctl is-active --quiet naiveguard.timer 2>/dev/null; then
        green "✓ NaiveGuard watchdog: active"
    else
        yellow "○ NaiveGuard: not installed (run option 16)"
    fi

    # Auto-updates
    if systemctl is-active --quiet unattended-upgrades 2>/dev/null || systemctl is-active --quiet dnf-automatic.timer 2>/dev/null; then
        green "✓ Auto security updates: enabled"
    else
        yellow "○ Auto updates: not configured"
    fi

    # Activity simulation
    if systemctl is-active --quiet webghost-activity.timer 2>/dev/null; then
        green "✓ Activity simulation: active (hourly)"
    else
        yellow "○ Activity simulation: not running"
    fi
	
	if [[ -n "${REMOTE_SERVER:-}" ]]; then
        green "✓ Mutual imitation: active (${REMOTE_SERVER})"
    else
        yellow "○ Mutual imitation: not configured"
    fi

    # External reachability
    local server_ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "unknown")
    if [[ "$server_ip" != "unknown" ]]; then
        if timeout 3 bash -c "echo >/dev/tcp/$server_ip/443" 2>/dev/null; then
            green "✓ Port 443: reachable from internet"
        else
            red "✗ Port 443: not reachable"
        fi
    else
        yellow "○ Could not determine external IP"
    fi

    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    echo -e " ${BLUE}Bash:${PLAIN} ${BASH_VERSION}  ${BLUE}Kernel:${PLAIN} $(uname -r)  ${BLUE}Host:${PLAIN} $(hostname)"
    yellow "═══════════════════════════════════════════════════════════════"
}

# =====================================
# Function: NaiveProxy Installation
# =====================================
install_naiveproxy() {
    show_header
    
	if is_naive_installed; then
		yellow "NaiveProxy is already installed!"
		while true; do
			echo ""
			read -rp "Do you want to reinstall? [Y/n]: " reinstall
			case $reinstall in
				[Nn]*)
					green "Installation cancelled"
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
    
    green "Starting installation of NaiveProxy ..."
    local current_ssh_port=22
    
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
	if ! install_webghost; then
        red "✗ WebGhost installation failed – aborting"
        exit 1
    fi
    create_landing_page
    create_configs
    create_systemd_service
    enable_bbr

    if systemctl is-active --quiet caddy; then
        green "\n✓ NaiveProxy successfully installed and running!"
        echo "Client configuration saved in /root/naive/"
        
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
          
		setup_auto_update_cron
		setup_random_activity
		setup_naiveguard
		setup_custom_prompt
		
		show_install_checklist
        
        if [[ $SSH_PORT -ne $current_ssh_port ]]; then
            echo ""
            yellow "═══════════════════════════════════════════════════════════════"
            yellow "                   SSH Port Changed"
            yellow "═══════════════════════════════════════════════════════════════"
            echo ""
            yellow "○ SSH port changed from $current_ssh_port to $SSH_PORT"
            yellow "○ Your current connection remains active on port $current_ssh_port"
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
        red "Error starting Caddy! Check logs: journalctl -u caddy -n 50"
        exit 1
    fi
    
    show_footer
}

# =====================================
# Function: Remove NaiveProxy
# =====================================
uninstall_naiveproxy() {
    show_header
    
    yellow "○ This will remove NaiveProxy and ALL related files!"
    yellow "  - Caddy service and binary"
    yellow "  - SSL certificates"
    yellow "  - Client configurations"
	yellow "  - Random website activity timer"
    echo ""
    
    # Показываем, что будет сохранено
    if [[ -d /root/naive ]]; then
        echo "  Backup folder exists: /root/naive/"
        echo "    - runtime.env (config)"
        echo "    - cert-backup/ (SSL certificates)"
        echo "    - users/ (user accounts)"
        echo ""
    fi
	
    # Удаляем WebGhost activity (если использовалась)
    systemctl stop webghost-activity.timer 2>/dev/null
    systemctl disable webghost-activity.timer 2>/dev/null
    rm -f /etc/systemd/system/webghost-activity.{service,timer}
    rm -f /usr/local/bin/webghost-activity.sh
    rm -f /var/log/website-activity.log
    rm -f /etc/logrotate.d/website-activity
    rm -f /usr/local/bin/webghost
	rm -rf /var/www/html/*
    systemctl daemon-reload
    
    read -rp "Remove configuration backup as well? [y/N]: " remove_backup
    
    # Перезапускаем Caddy
    systemctl stop caddy 2>/dev/null
    systemctl disable caddy 2>/dev/null
    sleep 2
    pkill -x caddy 2>/dev/null
    sleep 1
    
    rm -rf /etc/caddy
    rm -rf /usr/bin/caddy
    rm -rf /etc/systemd/system/caddy.service
    rm -rf /var/lib/caddy 2>/dev/null
    rm -rf /root/.local/share/caddy 2>/dev/null
    rm -rf /root/go /root/tmp
    
    sed -i '/export PATH=\$PATH:\/usr\/local\/go\/bin/d' ~/.bashrc
    
    # Удаляем конфиги только если пользователь явно сказал YES
    if [[ "$remove_backup" =~ ^[Yy]$ ]]; then
        rm -rf /root/naive
        green "✓ Configuration backup removed"
    else
        green "✓ Configuration backup kept at /root/naive/"
    fi
    
    systemctl daemon-reload
    
    green "✓ NaiveProxy removed!"
    echo ""
    echo -e "${YELLOW}Note:${PLAIN} Go (/usr/local/go) not removed to avoid damaging other projects"
    echo -e "To remove Go: ${YELLOW}rm -rf /usr/local/go${PLAIN}"
    
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
# Function: Run proxy
# =====================================
start_naiveproxy() {
    if ! is_naive_installed; then
        yellow "NaiveProxy is not installed! Please install it first (step 1)"
        return 0
    fi
    
    if systemctl is-active --quiet caddy; then
        yellow "NaiveProxy is already running"
        return 0
    fi
    
	# Проверяем, что порт всё ещё свободен (мог быть занят между установкой и запуском)
	load_runtime_config
	if ss -tlnp | grep -q ":$proxyport "; then
		local pid_info=$(ss -tlnp | grep ":$proxyport " | awk '{print $NF}')
		red "✗ Port $proxyport is in use: $pid_info"
		return 1
	fi
	
    systemctl start caddy
    sleep 2
    
    if systemctl is-active --quiet caddy; then
        green "✓ NaiveProxy started"
    else
        red "✗ Failed to start Caddy. Check logs: journalctl -u caddy -n 30"
        return 1
    fi
}

# =====================================
# Function: Stop proxy
# =====================================
stop_naiveproxy() {
    if ! is_naive_installed; then
        yellow "NaiveProxy is not installed! Please install it first (step 1)"
        return 0
    fi
    
    if ! systemctl is-active --quiet caddy; then
        yellow "NaiveProxy is already stopped"
        return 0
    fi
    
    systemctl stop caddy
    sleep 1
    green "✓ NaiveProxy stopped"
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
    sleep 2
    
    if systemctl is-active --quiet caddy; then
        green "✓ NaiveProxy restarted"
    else
        red "✗ Failed to restart Caddy. Check logs: journalctl -u caddy -n 30"
        return 1
    fi
}

# =====================================
# Function: Show client configuration
# =====================================
show_config() {
    show_header
    
    if ! is_naive_installed; then
        yellow "NaiveProxy is not installed! Please install it first (step 1)"
        show_footer
        return 0
    fi
    
    if [[ -f /root/naive/runtime.env ]]; then
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
        green "QR code for importing to your smartphone:"
        echo ""
        qrencode -t ANSIUTF8 "$(cat /root/naive/naive-url.txt)" 2>/dev/null || yellow "○ QR code generation error"
    elif ! command -v qrencode &>/dev/null; then
        yellow "○ Tip: Install 'qrencode' to generate QR codes"
    fi
    
    show_footer
}

# =====================================
# Function: Show user registry
# =====================================
show_user_registry() {
    show_header
    
    if ! is_naive_installed; then
        yellow "NaiveProxy is not installed!"
        show_footer
        return 0
    fi

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
            local padded_id=$(printf "%4s" "$id")
            local name_padding=$(printf '%*s' $((30 - ${#short_name})) "")
            local user_padding=$(printf '%*s' $((8 - ${#short_username})) "")
                        
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
        # Ищем точное совпадение ID (с учётом пробелов)
        local user_data=$(grep "^[[:space:]]*${view_id}[[:space:]]*|" /root/naive/registry.txt 2>/dev/null)
        
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
            blue "═══════════════════════════════════════════════════════════════"
            green "                      User Details"
            blue "═══════════════════════════════════════════════════════════════"
            echo ""
            echo -e "${GREEN}Name:${PLAIN}     $name"
            echo -e "${GREEN}ID:${PLAIN}       $id"
			echo -e "${GREEN}Created:${PLAIN}  $created"
			echo ""
			echo -e "${GREEN}Server:${PLAIN}   ${domain}"
			echo -e "${GREEN}Port:${PLAIN}     ${proxyport}"
            echo -e "${GREEN}Username:${PLAIN} $username"
            echo -e "${GREEN}Password:${PLAIN} $password"           
            echo ""
            echo -e "${GREEN}Connection URL:${PLAIN}"
            echo "naive+https://${username}:${password}@${domain}:${proxyport}?padding=true#Naive-${name}"
            
            local user_dir="/root/naive/users/user_$(printf "%03d" $id)_${username}"
            if [[ -f "$user_dir/qr.txt" ]]; then
                echo ""
                cat "$user_dir/qr.txt"
            fi
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
        yellow "NaiveProxy is not installed!"
        show_footer
        return 0
    fi
    
    load_runtime_config
    
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
            yellow "Name cannot be empty. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if [[ ${#user_name} -lt 2 ]]; then
            attempts=$((attempts + 1))
            yellow "Name must be at least 2 characters. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if [[ "$user_name" =~ [\|\\\&\;\`\$\(\)] ]]; then
            attempts=$((attempts + 1))
            yellow "Name contains invalid characters. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if [[ -f /root/naive/registry.txt ]]; then
            if grep -qi "|.*|.*|.*${user_name}[[:space:]]*|" /root/naive/registry.txt 2>/dev/null; then
                attempts=$((attempts + 1))
                yellow "User '$user_name' already exists. Attempt $attempts of $max_attempts"
                continue
            fi
        fi
        
        # Подтверждение ввода
        echo ""
        read -rp "Confirm user name '$user_name'? [y/N]: " confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            break
        else
            yellow "○ Re-enter user name"
            echo ""
            continue
        fi
    done
    
    # Генерируем данные
    local username=$(openssl rand -hex 4)
    local password=$(openssl rand -hex 12)
    
    # Определяем следующий ID
    local next_id=1
    if [[ -f /root/naive/registry.txt ]] && [[ -s /root/naive/registry.txt ]]; then
        next_id=$(($(tail -1 /root/naive/registry.txt | cut -d'|' -f1 | xargs) + 1))
    fi
    
    local created_date=$(date +%Y-%m-%d)
    
	# Создаём временный файл, копируем оригинал
	local caddy_tmp=$(mktemp)
	cp /etc/caddy/Caddyfile "$caddy_tmp"
	cp /etc/caddy/Caddyfile "${caddy_tmp}.backup"

	# Добавляем нового пользователя (ищем первый forward_proxy блок)
	sed -i "0,/forward_proxy {/!b; /forward_proxy {/a\\        basic_auth ${username} ${password}" "$caddy_tmp"

	# Применяем временный файл и валидируем
	mv "$caddy_tmp" /etc/caddy/Caddyfile
	if ! caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
		red "✗ Caddyfile validation failed! Rolling back ..."
		cp "${caddy_tmp}.backup" /etc/caddy/Caddyfile
		rm -f "$caddy_tmp" "${caddy_tmp}.backup"
		systemctl restart caddy   # на всякий случай, если уже был запущен
		return 1
	fi

	# Если валидация прошла, удаляем бекап
	rm -f "${caddy_tmp}.backup"
    
    # Создаём папку пользователя
    local user_dir="/root/naive/users/user_$(printf "%03d" $next_id)_${username}"
    mkdir -p "$user_dir"

    # Создаём конфиг
    cat > "$user_dir/config.json" << EOF
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://${username}:${password}@${domain}:${proxyport}",
  "log": ""
}
EOF
    
    # Создаём URL
    local url="naive+https://${username}:${password}@${domain}:${proxyport}?padding=true#Naive-${user_name}"
    echo "$url" > "$user_dir/url.txt"
	chmod 600 "$user_dir/config.json"
	chmod 600 "$user_dir/url.txt"
	[[ -f "$user_dir/qr.txt" ]] && chmod 600 "$user_dir/qr.txt"
	
    # Генерируем QR код
    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$url" > "$user_dir/qr.txt" 2>/dev/null
    fi
    
    # Добавляем в реестр
    echo "$next_id | $username | $password | $user_name | $created_date" >> /root/naive/registry.txt
	
    systemctl restart caddy 2>/dev/null
	
	if ! systemctl is-active --quiet caddy; then
		red "✗ Caddy failed to restart! Check: journalctl -u caddy -n 30"
		return 1
	fi
    
    echo ""
    green "✓ User '$user_name' added!"
    echo ""
    echo -e "${GREEN}Name:${PLAIN}     $user_name"
    echo -e "${GREEN}ID:${PLAIN}       $next_id"
	echo ""
	echo -e "${GREEN}Server:${PLAIN}   ${domain}"
	echo -e "${GREEN}Port:${PLAIN}     ${proxyport}"
    echo -e "${GREEN}Username:${PLAIN} $username"
    echo -e "${GREEN}Password:${PLAIN} $password"
    echo ""
    echo -e "${GREEN}URL:${PLAIN}"
    echo "$url"
    echo ""
    echo -e "${GREEN}Config:${PLAIN} $user_dir/config.json"
    
    if [[ -f "$user_dir/qr.txt" ]]; then
        echo ""
        cat "$user_dir/qr.txt"
    fi
    
	rm -f "$caddy_tmp" "${caddy_tmp}.backup"
	
    show_footer
}

# =====================================
# Function: Remove user
# =====================================
remove_user() {
    while true; do
        show_header
        
        if ! is_naive_installed; then
            yellow "NaiveProxy is not installed!"
            show_footer
            return 0
        fi
        
        load_runtime_config
        
        blue "═══════════════════════════════════════════════════════════════"
        green "                      Remove User"
        blue "═══════════════════════════════════════════════════════════════"
        
        # Собираем пользователей и определяем max_id_width
        local users=()
        local max_id_width=2
        
        if [[ -f /root/naive/registry.txt ]]; then
            while IFS='|' read -r id username password name created; do
                id=$(echo "$id" | xargs)
                username=$(echo "$username" | xargs)
                name=$(echo "$name" | xargs)
                users+=("$id|$username|$name")
                
                if [[ ${#id} -gt $max_id_width ]]; then
                    max_id_width=${#id}
                fi
            done < /root/naive/registry.txt
        fi
        
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
				local padded_id=$(printf "%4s" "$id")
				local name_padding=$(printf '%*s' $((30 - ${#short_name})) "")
				local user_padding=$(printf '%*s' $((8 - ${#short_username})) "")
							
				echo -e "  ${padded_id} ${BLUE}|${PLAIN} ${short_name}${name_padding} ${BLUE}|${PLAIN} ${short_username}${user_padding} ${BLUE}|${PLAIN} ${created}"
			done < /root/naive/registry.txt
		fi
        
        echo ""
        yellow "═══════════════════════════════════════════════════════════════"
        
        read -rp "Enter ID to remove (or 0 to return to menu): " remove_id
        
        if [[ "$remove_id" == "0" ]] || [[ -z "$remove_id" ]]; then
            green "Returning to menu ..."
            break
        fi
        
        # Ищем пользователя
        local user_data=$(grep "^[[:space:]]*${remove_id}[[:space:]]*|" /root/naive/registry.txt 2>/dev/null)
        
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
        yellow "Remove user '$name' (ID: $id)?"
        read -rp "Type 'YES' to confirm: " confirm
        
        if [[ "$confirm" != "YES" ]]; then
            green "Cancelled"
            read -rp "Press Enter to continue ..."
            continue
        fi
        
		# Создаём временный файл с бекапом
		local caddy_tmp=$(mktemp)
		cp /etc/caddy/Caddyfile "$caddy_tmp"
		cp /etc/caddy/Caddyfile "${caddy_tmp}.backup"

		# Удаляем строку с пользователем
		sed -i "/basic_auth ${username} ${password}/d" "$caddy_tmp"

		# Применяем и валидируем
		mv "$caddy_tmp" /etc/caddy/Caddyfile
		if ! caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
			red "✗ Caddyfile validation failed! Rolling back ..."
			cp "${caddy_tmp}.backup" /etc/caddy/Caddyfile
			rm -f "$caddy_tmp" "${caddy_tmp}.backup"
			systemctl restart caddy
			return 1
		fi

		rm -f "${caddy_tmp}.backup"
        
        # Удаляем из реестра
        sed -i "/^[[:space:]]*${id}[[:space:]]*|/d" /root/naive/registry.txt
        
        # Удаляем папку пользователя
        rm -rf "/root/naive/users/user_$(printf "%03d" $id)_${username}"
        
        # Перезапускаем Caddy
        systemctl restart caddy 2>/dev/null
		
		if ! systemctl is-active --quiet caddy; then
			red "✗ Caddy failed to restart! Check: journalctl -u caddy -n 30"
			return 1
		fi
        
        green "✓ User '$name' removed"
        echo ""
        read -rp "Press Enter to continue removing another user ..."
    done
    
    show_footer
}

# =====================================
# Function: Validate configuration and certificates
# =====================================
validate_configuration() {
    local errors=0
    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    yellow "                   Configuration Validation"
    yellow "═══════════════════════════════════════════════════════════════"
    echo ""
    
    if [[ -f /root/naive/runtime.env ]]; then
        source /root/naive/runtime.env
        green "✓ Configuration file loaded"
    else
        red "✗ Configuration file not found at /root/naive/runtime.env"
        errors=$((errors+1))
    fi
    
    [[ -z "$domain" ]] && { red "✗ Domain is missing"; errors=$((errors+1)); } || green "✓ Domain: $domain"
    [[ -z "$proxyport" ]] && { red "✗ Proxy port is missing"; errors=$((errors+1)); } || green "✓ Proxy port: $proxyport"
    [[ -z "$proxyname" ]] && { red "✗ Username is missing"; errors=$((errors+1)); } || green "✓ Username: $proxyname"
    [[ -z "$proxypwd" ]] && { red "✗ Password is missing"; errors=$((errors+1)); } || green "✓ Password: [set]"
    [[ -z "$email" ]] && { red "✗ Email is missing"; errors=$((errors+1)); } || green "✓ Email: $email"
    [[ -z "$SSH_PORT" ]] && { red "✗ SSH port is missing"; errors=$((errors+1)); } || green "✓ SSH port: $SSH_PORT"
    
    if [[ -n "$proxyport" ]] && [[ ! "$proxyport" =~ ^[0-9]+$ ]]; then
        red "✗ Proxy port is not a number: $proxyport"
        errors=$((errors+1))
    fi
    
    if [[ -n "$domain" ]] && ! echo "$domain" | grep -qP '^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$'; then
        red "✗ Domain format is invalid: $domain"
        errors=$((errors+1))
    fi
    
    echo ""
    yellow "SSL Certificate Status:"
    CERT_FILE=$(find /var/lib/caddy/.local/share/caddy /root/.local/share/caddy -name "${domain}.crt" 2>/dev/null | head -1)
    
    if [[ -n "$CERT_FILE" ]] && [[ -f "$CERT_FILE" ]]; then
        CERT_EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)
        CERT_ISSUER=$(openssl x509 -issuer -noout -in "$CERT_FILE" 2>/dev/null | sed 's/issuer=//' | xargs)
        CERT_DOMAIN=$(openssl x509 -subject -noout -in "$CERT_FILE" 2>/dev/null | grep -oP 'CN=\K[^,]+' || echo "$domain")
        
        EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s 2>/dev/null)
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
        
        if [[ $DAYS_LEFT -lt 0 ]]; then
            red "✗ SSL certificate has EXPIRED"
            errors=$((errors+1))
        elif [[ $DAYS_LEFT -lt 7 ]]; then
            yellow "○ SSL certificate expires in $DAYS_LEFT days"
        else
            green "✓ SSL certificate is valid (expires in $DAYS_LEFT days)"
        fi
        
        green "  Domain: $CERT_DOMAIN"
        green "  Issuer: $CERT_ISSUER"
        green "  Expires: $CERT_EXPIRY"
    else
        red "✗ SSL certificate not found for domain $domain"
        errors=$((errors+1))
    fi
    
    echo ""
    yellow "Connectivity Check:"
    SERVER_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "unknown")
    if [[ "$SERVER_IP" != "unknown" ]]; then
        if timeout 3 bash -c "echo >/dev/tcp/$SERVER_IP/443" 2>/dev/null; then
            green "✓ Port 443 is reachable from internet"
        else
            red "✗ Port 443 is NOT reachable from internet"
            yellow "  ○ Check firewall and NAT settings"
            errors=$((errors+1))
        fi
    else
        yellow "○ Could not determine external IP"
    fi
    
    echo ""
    yellow "═══════════════════════════════════════════════════════════════"
    if [[ $errors -eq 0 ]]; then
        green "✓ VALIDATION PASSED — all systems ready"
        return 0
    else
        red "✗ VALIDATION FAILED — found $errors error(s)"
        yellow "  ○ Run 'Install' again or check logs: journalctl -u caddy -n 50"
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
    yellow "Setting up custom bash prompt (Kordan style) ..."
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
    check_system_requirements
    
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}    Proxy Management${PLAIN}"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}1.  Install${PLAIN}   NaiveProxy"
    echo -e " ${RED}2.  Uninstall${PLAIN} NaiveProxy"
	echo -e " ${YELLOW}3.  Update/Rebuild${PLAIN} NaiveProxy"
    echo " ----------------"
    echo -e " ${GREEN}4.${PLAIN}  Start     NaiveProxy"
    echo -e " ${GREEN}5.${PLAIN}  Stop      NaiveProxy"
    echo -e " ${GREEN}6.${PLAIN}  Restart   NaiveProxy"	
	
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}    User Management${PLAIN}"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
	echo -e " ${GREEN}7.${PLAIN}  Show   user registry"
	echo -e " ${GREEN}8.  Add${PLAIN}    user"
	echo -e " ${RED}9.  Remove${PLAIN} user"
	
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}    Server Management${PLAIN}"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}10.${PLAIN} System info"
    echo -e " ${GREEN}11.${PLAIN} System maintenance"
    echo -e " ${YELLOW}12. Reboot${PLAIN} server"	
	
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}    Certificate Management${PLAIN}"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}13.${PLAIN} Backup certificates"
    echo -e " ${GREEN}14.${PLAIN} Restore certificates"
    echo -e " ${GREEN}15.${PLAIN} Check certificate status"
        
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"
    echo -e " ${GREEN}0.${PLAIN}  Exit"
    echo -e " ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${PLAIN}"   
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
        read -rp " Your choice [0-15]: " answer
        
        if [[ -z "$answer" ]]; then
            attempts=$((attempts + 1))
            yellow "Enter a number from 0 to 15. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if ! echo "$answer" | grep -qE '^[0-9]+$'; then
            attempts=$((attempts + 1))
            yellow "Enter a number. Attempt $attempts of $max_attempts"
            continue
        fi
        
        if [[ $answer -lt 0 ]] || [[ $answer -gt 15 ]]; then
            attempts=$((attempts + 1))
            yellow "Number must be between 0 and 15. Attempt $attempts of $max_attempts"
            continue
        fi
        
        break
    done
    
    case $answer in
        # Proxy Management
        1) install_naiveproxy ;;
        2) uninstall_naiveproxy ;;
		3) check_and_update_naive ;;
        4) start_naiveproxy ;;
        5) stop_naiveproxy ;;
        6) restart_naiveproxy ;;
		
		# User Management
        7) show_user_registry ;;
		8) add_new_user ;;
		9) remove_user ;;
        
        # Server Management
        10) show_system_info ;;
        11) system_maintenance ;;
        12) reboot_server ;;		
		
        # Certificate Management
        13) backup_certificates ;;
        14) restore_certificates ;;
        15) check_certificate_status ;;
                
        # Exit
        0) clear && exit 0 ;;
    esac
    
    if [[ $answer != "0" ]]; then
        echo ""
        read -rp "Press Enter to return to menu ..."
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
