#!/bin/bash
# ===========================================================================
# Название:        NaiveProxy Installer
# Описание:        Автоматическая установка NaiveProxy с последней версией Go
# Автор:           Kordan (krdn-dev)
# GitHub:          https://github.com/krdn-dev/naiveproxy-installer
# Лицензия:        MIT
# ===========================================================================

export LANG=en_US.UTF-8

# =====================================
# Цвета и стили
# =====================================
RED="\033[91m"
GREEN="\033[92m"
YELLOW="\033[33m"
BLUE="\033[94m"
PLAIN="\033[0m"

red() { echo -e "${RED}${1}${PLAIN}"; }
green() { echo -e "${GREEN}${1}${PLAIN}"; }
yellow() { echo -e "${YELLOW}${1}${PLAIN}"; }

# =====================================
# Определение системы
# =====================================
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")

# =====================================
# Функция: Проверка системных требований
# =====================================
check_system_requirements() {
    # ----- Проверка root -----
    if [[ $EUID -ne 0 ]]; then
        red "ВНИМАНИЕ: Запустите скрипт от пользователя root"
        exit 1
    fi
    
    # ----- Определение системы -----
    CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")
    
    for i in "${CMD[@]}"; do
        SYS="$i" && [[ -n $SYS ]] && break
    done
    
    for ((int = 0; int < ${#REGEX[@]}; int++)); do
        [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && break
    done
    
    if [[ -z $SYSTEM ]]; then
        red "Ваша операционная система не поддерживается!"
        exit 1
    fi
    
    # ----- Проверка минимальных версий ОС -----
    case $SYSTEM in
        "Debian")
            VERSION=$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release 2>/dev/null)
            [[ -z $VERSION ]] && VERSION=$(grep -oP '(?<=VERSION=)[0-9]+' /etc/os-release 2>/dev/null)
            if [[ $VERSION -lt 11 ]]; then
                red "Debian $VERSION слишком старый! Требуется Debian 11 или новее."
                exit 1
            fi
            ;;
        "Ubuntu")
            VERSION=$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release 2>/dev/null)
            if [[ $VERSION -lt 20 ]]; then
                red "Ubuntu $VERSION слишком старый! Требуется Ubuntu 20.04 или новее."
                exit 1
            fi
            ;;
        "CentOS")
            if [[ -f /etc/centos-release ]]; then
                VERSION=$(grep -oE '[0-9]+' /etc/centos-release | head -1)
                if [[ $VERSION -lt 8 ]]; then
                    red "CentOS $VERSION слишком старый! Требуется CentOS 8 или новее."
                    exit 1
                fi
            fi
            ;;
        "Fedora")
            VERSION=$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release 2>/dev/null)
            if [[ $VERSION -lt 37 ]]; then
                red "Fedora $VERSION слишком старый! Требуется Fedora 37 или новее."
                exit 1
            fi
            ;;
    esac
    
    green "Система: $SYSTEM $VERSION (поддерживается)"
}

# =====================================
# Функция: Проверка архитектуры, RAM, диска
# =====================================
check_hardware_requirements() {
    # ----- Проверка архитектуры процессора -----
    case "$(uname -m)" in
        x86_64|amd64) green "Архитектура: x86_64" ;;
        aarch64|arm64) green "Архитектура: ARM64" ;;
        *) red "Неподдерживаемая архитектура: $(uname -m)"; exit 1 ;;
    esac
    
    # ----- Проверка RAM -----
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_RAM -lt 256 ]]; then
        red "Недостаточно оперативной памяти: ${TOTAL_RAM}MB (требуется минимум 256MB)"
        exit 1
    elif [[ $TOTAL_RAM -lt 512 ]]; then
        yellow "Оперативной памяти ${TOTAL_RAM}MB может быть недостаточно для компиляции Caddy"
    else
        green "Оперативная память: ${TOTAL_RAM}MB"
    fi
    
    # ----- Проверка свободного места -----
    FREE_SPACE=$(df -m / | awk 'NR==2 {print $4}')
    if [[ $FREE_SPACE -lt 1024 ]]; then
        red "Недостаточно свободного места: ${FREE_SPACE}MB (требуется минимум 1GB)"
        exit 1
    else
        green "Свободное место: ${FREE_SPACE}MB"
    fi
}

# =====================================
# Функция: Установка базовых пакетов
# =====================================
install_base_packages() {
    yellow "Установка базовых пакетов ..."
    
    # ----- Обновление списка пакетов (аккуратно для CentOS) -----
    if [[ $SYSTEM == "CentOS" ]] && [[ ${VERSION:-0} -ge 8 ]]; then
        ${PACKAGE_UPDATE[int]} 2>/dev/null || true
    elif [[ $SYSTEM != "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    
    # ----- Установка общих пакетов -----
    ${PACKAGE_INSTALL[int]} curl wget git
    
    # ----- Установка dnsutils для dig -----
    if ! command -v dig &>/dev/null; then
        yellow "Установка dnsutils (dig)..."
        ${PACKAGE_INSTALL[int]} dnsutils 2>/dev/null || ${PACKAGE_INSTALL[int]} bind-utils 2>/dev/null
    fi
    
    # ----- Установка компиляторов -----
    if [[ $SYSTEM == "Debian" ]] || [[ $SYSTEM == "Ubuntu" ]]; then
        ${PACKAGE_INSTALL[int]} build-essential
    else
        ${PACKAGE_INSTALL[int]} gcc gcc-c++ make
    fi
    
    # ----- qrencode — опционально -----
    ${PACKAGE_INSTALL[int]} qrencode 2>/dev/null || yellow "qrencode не установлен (QR-коды не будут работать)"
    
    green "Базовые пакеты установлены"
}

# =====================================
# Функция: Установка Go
# =====================================
install_go() {
    yellow "Проверка последней версии Go ..."

    LATEST_GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1)

    if [[ -z "$LATEST_GO_VERSION" ]]; then
        red "Не удалось получить последнюю версию Go. Проверьте соединение"
        exit 1
    fi

    GO_VERSION="${LATEST_GO_VERSION#go}"
	green "Последняя стабильная версия: $GO_VERSION"

    # ----- Определяем архитектуру -----
    if [[ "$(uname -m)" == "x86_64" ]]; then
        ARCH="amd64"
    elif [[ "$(uname -m)" == "aarch64" ]]; then
        ARCH="arm64"
    else
        red "Неподдерживаемая архитектура процессора: $(uname -m)"
        exit 1
    fi

    GO_ARCHIVE="${LATEST_GO_VERSION}.linux-${ARCH}.tar.gz"
    DOWNLOAD_URL="https://go.dev/dl/${GO_ARCHIVE}"

    rm -rf /usr/local/go

    yellow "Скачивание $LATEST_GO_VERSION для linux/$ARCH ..."
    wget -q --show-progress "$DOWNLOAD_URL" -O /tmp/go.tar.gz

    if [[ $? -ne 0 ]]; then
        red "Ошибка при скачивании Go. Пожалуйста, проверьте соединение"
        exit 1
    fi

    yellow "Установка Go в /usr/local ..."
    tar -C /usr/local -xzf /tmp/go.tar.gz

    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    export PATH=$PATH:/usr/local/go/bin

    rm -f /tmp/go.tar.gz

    if ! command -v go &>/dev/null; then
        red "Ошибка: Go не был установлен"
        exit 1
    fi

    green "Go ${GO_VERSION} успешно установлен!"
}

# =====================================
# Функция: Сборка Caddy с плагином forwardproxy
# =====================================
build_caddy() {
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

    mkdir -p /root/tmp
    export TMPDIR=/root/tmp

    yellow "Сборка Caddy с плагином forwardproxy (может занять 3-5 минут) ..."
    ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive

    mv caddy /usr/bin/caddy
    chmod +x /usr/bin/caddy
}

# =====================================
# Функция: Ввод параметров от пользователя
# =====================================
input_parameters() {
    yellow "Ввод данных ..."
    
    # ----- Ввод порта -----
    while true; do    
        echo "Введите порт для NaiveProxy (рекомендуется 443): "
        echo "Доступные варианты для порта:"
        echo "  1) 443  (Рекомендуется. Лучшая маскировка)"
        echo "  2) 8443 (Альтернативный, часто разрешен в корпоративных сетях)"
        echo "  3) Свой вариант (диапазон от 1024 до 65535)"
        read -rp "Ваш выбор [1-3]: " port_choice

        case $port_choice in
            1)
                proxyport=443
                break
                ;;
            2)
                proxyport=8443
                break
                ;;
            3)
                read -rp "Введите номер порта (1024-65535): " proxyport
                if [[ "$proxyport" =~ ^[0-9]+$ ]] && [ "$proxyport" -ge 1024 ] && [ "$proxyport" -le 65535 ]; then
                    break
                else
                    red "Ошибка: Нужно ввести число от 1024 до 65535"
                fi
                ;;
            *)
                red "Неверный выбор"
                ;;
        esac
    done

    # ----- Проверка занятости порта -----
    if ss -tlnp | grep -q ":$proxyport "; then
        red "Порт $proxyport уже занят другим процессом!"
        exit 1
    fi

    green "Порт $proxyport выбран и свободен"

    # ----- Ввод домена -----
    while true; do
        read -rp "Введите ваш домен (например, example.com): " domain
        
        if [[ -z $domain ]]; then
            red "Домен не может быть пустым!"
            continue
        fi
        
        if ! echo "$domain" | grep -qP '^(?=[a-z0-9-]{1,63}\.)([a-z0-9-]+\.)+[a-z]{2,}$'; then
            red "Некорректный формат домена! Пример: example.com"
            continue
        fi
        
        yellow "Проверка DNS ..."
        SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || curl -s --max-time 5 ipinfo.io/ip 2>/dev/null)
        DOMAIN_IP=$(dig +short "$domain" | head -1)
        
        if [[ -z "$DOMAIN_IP" ]]; then
            red "Домен $domain не резолвится в IP-адрес! Проверьте DNS записи"
            yellow "Вы можете исправить DNS и ввести домен снова"
            continue
        fi
        
        if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
            red "Домен $domain указывает на $DOMAIN_IP, а IP сервера: $SERVER_IP"
            red "Исправьте A-запись домена!"
            yellow "После исправления DNS введите домен снова"
            continue
        fi
        
        green "DNS проверка пройдена: домен → $DOMAIN_IP"
        break
    done

    # ----- Ввод email -----
    while true; do
        read -rp "Введите email для сертификатов Let's Encrypt: " email
        
        if [[ -z $email ]]; then
            red "Email не может быть пустым!"
            continue
        fi
        
        if ! echo "$email" | grep -qP '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
            red "Некорректный формат email! Пример: user@example.com"
            continue
        fi
        
        green "Email корректен"
        break
    done

    # ----- Ввод имени пользователя -----
    while true; do
        read -rp "Введите имя пользователя [Enter для случайного]: " proxyname
        
        if [[ -z $proxyname ]]; then
            if command -v openssl &>/dev/null; then
                proxyname=$(openssl rand -hex 8)
            else
                proxyname=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16)
            fi
            green "Сгенерировано имя пользователя: $proxyname"
            break
        else
            if [[ ${#proxyname} -lt 3 ]]; then
                red "Имя пользователя должно содержать минимум 3 символа!"
                continue
            fi
            break
        fi
    done

    # ----- Ввод пароля -----
    while true; do
        read -rp "Введите пароль [Enter для случайного]: " proxypwd
        
        if [[ -z $proxypwd ]]; then
            if command -v openssl &>/dev/null; then
                proxypwd=$(openssl rand -hex 12)
            else
                proxypwd=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 24)
            fi
            green "Сгенерирован пароль: $proxypwd"
            break
        else
            if [[ ${#proxypwd} -lt 6 ]]; then
                red "Пароль должен содержать минимум 6 символов!"
                continue
            fi
            break
        fi
    done

    # ----- Ввод адреса маскировки -----
    while true; do
        read -rp "Введите адрес для маскировки (без https://, Enter = wikipedia.org): " proxysite
        [[ -z $proxysite ]] && proxysite="wikipedia.org"

        proxysite=$(echo "$proxysite" | sed 's|^https\?://||')

        if ! echo "$proxysite" | grep -qP '^[a-z0-9.-]+\.[a-z]{2,}$'; then
            yellow "Внимание: Адрес маскировки '$proxysite' выглядит необычно"
            read -rp "Продолжить с этим адресом? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                yellow "Пожалуйста, введите другой адрес маскировки"
                continue
            fi
        fi

        yellow "Проверка доступности сайта маскировки ..."
        if curl -s -o /dev/null -L --max-time 10 "https://$proxysite"; then
            green "Сайт маскировки доступен"
            break
        else
            yellow "Внимание: Сайт $proxysite не отвечает по HTTPS"
            yellow "Маскировка может работать нестабильно или привлекать внимание"
            read -rp "Всё равно продолжить с этим сайтом? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                yellow "Продолжаем с сайтом $proxysite (доступность не гарантирована)"
                break
            else
                yellow "Пожалуйста, введите другой адрес маскировки"
                continue
            fi
        fi
    done
}

# =====================================
# Функция: Создание конфигурационных файлов
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
}

:80 {
    redir https://${domain}:${proxyport}{uri} permanent
}
EOF

    # ----- Клиентская конфигурация -----
    mkdir -p /root/naive
    cat <<EOF > /root/naive/naive-client.json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://${proxyname}:${proxypwd}@${domain}:${proxyport}",
  "log": ""
}
EOF

    # ----- Ссылка для клиентов -----
    url="naive+https://${proxyname}:${proxypwd}@${domain}:${proxyport}?padding=true#Naive-${domain}"
    echo "$url" > /root/naive/naive-url.txt
}

# =====================================
# Функция: Создание systemd сервиса
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
# Функция: Включение BBR
# =====================================
enable_bbr() {
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        green "BBR включен"
    fi
}

# =====================================
# Функция: Установка NaiveProxy (основная)
# =====================================
install_naiveproxy() {
    green "Начинаю установку NaiveProxy ..."
    
    yellow "\nПроверка системных требований ..."
    check_system_requirements
    check_hardware_requirements
    
    install_base_packages
    install_go
    build_caddy
    input_parameters
    
    mkdir -p /etc/caddy /var/www/html
    create_configs
    create_systemd_service
    enable_bbr

    if systemctl is-active --quiet caddy; then
        green "\nNaiveProxy успешно установлен и запущен!"
        echo "Конфигурация клиента сохранена в /root/naive/"
        show_config
    else
        red "Ошибка запуска Caddy! Проверьте логи: journalctl -u caddy -n 50"
        exit 1
    fi
}

# =====================================
# Функция: Удаление NaiveProxy
# =====================================
uninstall_naiveproxy() {
    yellow "Удаление NaiveProxy ..."
    
    systemctl stop caddy 2>/dev/null
    systemctl disable caddy 2>/dev/null
    
    rm -rf /etc/caddy /root/naive /usr/bin/caddy /etc/systemd/system/caddy.service
    rm -rf /root/go /root/tmp
    
    sed -i '/export PATH=\$PATH:\/usr\/local\/go\/bin/d' ~/.bashrc
    
    systemctl daemon-reload
    
    green "NaiveProxy полностью удалён!"
    echo -e "${YELLOW}Примечание:${PLAIN} Go (/usr/local/go) не был удалён, чтобы не повредить другие возможные проекты"
    echo -e "Если вы хотите удалить Go, выполните команду: ${YELLOW}rm -rf /usr/local/go${PLAIN}"
}

# =====================================
# Функция: Проверка установки
# =====================================
is_naive_installed() {
    [[ -f /usr/bin/caddy ]] && [[ -f /etc/systemd/system/caddy.service ]] && [[ -f /root/naive/naive-client.json ]]
    return $?
}

# =====================================
# Функция: Запуск прокси
# =====================================
start_naiveproxy() {
    if ! is_naive_installed; then
        yellow "NaiveProxy не установлен! Сначала выполните установку (пункт 1)"
        return 0
    fi
    systemctl start caddy
    systemctl enable caddy 2>/dev/null
    green "NaiveProxy запущен"
}

# =====================================
# Функция: Остановка прокси
# =====================================
stop_naiveproxy() {
    if ! is_naive_installed; then
        yellow "NaiveProxy не установлен"
        return 0
    fi
    systemctl stop caddy
    green "NaiveProxy остановлен"
}

# =====================================
# Функция: Перезапуск прокси
# =====================================
restart_naiveproxy() {
    if ! is_naive_installed; then
        yellow "NaiveProxy не установлен! Сначала выполните установку (пункт 1)"
        return 0
    fi
    systemctl restart caddy
    green "NaiveProxy перезапущен"
}

# =====================================
# Функция: Показать конфигурацию клиента
# =====================================
show_config() {
    if ! is_naive_installed; then
        yellow "NaiveProxy не установлен! Сначала выполните установку (пункт 1)"
        echo ""
        return 0
    fi
    
    yellow "\n=== Конфигурация клиента ==="
    echo -e "${GREEN}JSON формат (файл: /root/naive/naive-client.json):${PLAIN}"
    cat /root/naive/naive-client.json
    echo ""
    echo -e "${GREEN}Ссылка для импорта (файл: /root/naive/naive-url.txt):${PLAIN}"
    cat /root/naive/naive-url.txt
    echo ""

    if command -v qrencode &>/dev/null; then
        green "QR-код для импорта на смартфон:"
        echo ""
        qrencode -t ANSIUTF8 "$(cat /root/naive/naive-url.txt)" 2>/dev/null || yellow "Ошибка генерации QR-кода"
    fi
    echo ""
}

# =====================================
# Функция: Главное меню
# =====================================
show_menu() {
    clear
    echo "#################################################"
    echo -e "${BLUE}⚡ 𝓚𝓸𝓻𝓭𝓪𝓷 ⚡${PLAIN}      ${GREEN}NaiveProxy Installer${PLAIN}"
    echo "#################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Установить NaiveProxy"
    echo -e " ${RED}2.${PLAIN} Удалить NaiveProxy"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} Запустить NaiveProxy"
    echo -e " ${GREEN}4.${PLAIN} Остановить NaiveProxy"
    echo -e " ${GREEN}5.${PLAIN} Перезапустить NaiveProxy"
    echo " -------------"
    echo -e " ${GREEN}6.${PLAIN} Показать конфигурацию клиента"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} Выйти"
    echo ""
    
    local attempts=0
    local max_attempts=3
    
    while true; do
        if [[ $attempts -ge $max_attempts ]]; then
            red "\nПревышено количество $max_attempts попыток. Выход"
            exit 1
        fi
        
        read -rp " Ваш выбор [0-6]: " answer
        
        if [[ -z "$answer" ]]; then
            attempts=$((attempts + 1))
            yellow "Ошибка: Введите число от 0 до 6. Попытка $attempts из $max_attempts"
            continue
        fi
        
        if ! echo "$answer" | grep -qE '^[0-9]+$'; then
            attempts=$((attempts + 1))
            yellow "Ошибка: Введите число. Попытка $attempts из $max_attempts"
            continue
        fi
        
        if [[ $answer -lt 0 ]] || [[ $answer -gt 6 ]]; then
            attempts=$((attempts + 1))
            yellow "Ошибка: Число от 0 до 6. Попытка $attempts из $max_attempts"
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
        read -rp "Нажмите Enter чтобы вернуться в меню ..."
        show_menu
    fi
}

# =====================================
# Старт скрипта
# =====================================
check_system_requirements
show_menu