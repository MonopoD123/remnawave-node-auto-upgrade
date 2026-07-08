#!/bin/bash

# ==========================================
# Автоустановщик Remnawave Node + Tuning
# Версия: 3.1
# ==========================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Глобальные переменные
NODE_PORT=""
DOMAIN=""
SECRET_KEY=""

# Проверка Root прав
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[Ошибка] Пожалуйста, запустите скрипт от имени root (sudo).${NC}"
  exit 1
fi

# Установка пути к скрипту
SCRIPT_PATH="$(readlink -f "$0")"

# Функция отрисовки баннера
show_banner() {
    clear
    echo -e "${BLUE}"
    echo "██████  ███████ ███    ███ ███    ██  █████  "
    echo "██   ██ ██      ████  ████ ████   ██ ██   ██ "
    echo "██████  █████   ██ ████ ██ ██ ██  ██ ███████ "
    echo "██   ██ ██      ██  ██  ██ ██  ██ ██ ██   ██ "
    echo "██   ██ ███████ ██      ██ ██   ████ ██   ██ "
    echo -e "           Установка Node + Настройки v3.1${NC}"
    echo ""
}

# --- ФУНКЦИЯ ПРОВЕРКИ СИСТЕМЫ ---
check_system() {
    echo -e "${BLUE}=== ПРОВЕРКА СИСТЕМЫ ===${NC}"
    echo ""
    
    # 1. Проверка ядра
    echo -e "${CYAN}1. Проверка ядра:${NC}"
    KERNEL_VERSION=$(uname -r | cut -d'-' -f1)
    KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d'.' -f1)
    KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d'.' -f2)
    
    echo -n "  Версия ядра: "
    echo -e "${CYAN}$KERNEL_VERSION${NC}"
    
    if [ "$KERNEL_MAJOR" -gt 4 ] || ([ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -ge 9 ]); then
        echo -e "  ${GREEN}✓ Ядро поддерживает BBR${NC}"
        BBR_SUPPORT=true
    else
        echo -e "  ${RED}✗ Ядро $KERNEL_VERSION не поддерживает BBR (нужно 4.9+)${NC}"
        echo -e "  ${YELLOW}  Рекомендуется обновить ядро:${NC}"
        echo -e "  ${YELLOW}  apt-get install -y linux-generic-hwe-22.04 && reboot${NC}"
        BBR_SUPPORT=false
    fi
    
    # 2. Проверка DNS (если домен задан)
    if [ -n "$DOMAIN" ]; then
        echo ""
        echo -e "${CYAN}2. Проверка DNS для домена $DOMAIN:${NC}"
        if command -v dig &> /dev/null; then
            DOMAIN_IP=$(dig +short $DOMAIN | head -1)
            SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
            
            if [ -n "$DOMAIN_IP" ] && [ -n "$SERVER_IP" ]; then
                echo -n "  IP домена: $DOMAIN_IP, IP сервера: $SERVER_IP - "
                if [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
                    echo -e "${GREEN}✓ DNS настроен корректно${NC}"
                    DNS_OK=true
                else
                    echo -e "${RED}✗ IP не совпадают!${NC}"
                    echo -e "  ${YELLOW}  Настройте DNS запись A для домена на IP $SERVER_IP${NC}"
                    DNS_OK=false
                fi
            else
                echo -e "  ${RED}✗ Не удалось определить IP${NC}"
                DNS_OK=false
            fi
        else
            echo -e "  ${YELLOW}⚠ dig не установлен, пропускаем проверку DNS${NC}"
            DNS_OK=true
        fi
    fi
    
    # 3. Проверка портов
    echo ""
    echo -e "${CYAN}3. Проверка доступности портов:${NC}"
    for port in 22 80 443 2222; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "  ${GREEN}✓ Порт $port открыт${NC}"
        else
            if [ "$port" = "2222" ]; then
                echo -e "  ${YELLOW}⚠ Порт $port не прослушивается (будет использован для ноды)${NC}"
            else
                echo -e "  ${YELLOW}⚠ Порт $port не прослушивается${NC}"
            fi
        fi
    done
    
    # 4. Информация о системе
    echo ""
    echo -e "${CYAN}4. Информация о системе:${NC}"
    echo -e "  OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Не определено")"
    echo -e "  Архитектура: $(uname -m)"
    echo -e "  CPU: $(nproc) ядер"
    echo -e "  RAM: $(free -h | grep Mem | awk '{print $2}')"
    echo -e "  Диск: $(df -h / | awk 'NR==2 {print $4}') свободно"
    
    # 5. Проверка Docker
    echo ""
    echo -e "${CYAN}5. Проверка Docker:${NC}"
    if command -v docker &> /dev/null; then
        echo -e "  ${GREEN}✓ Docker установлен${NC}"
        docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        echo -e "  Версия: $docker_version"
    else
        echo -e "  ${YELLOW}⚠ Docker не установлен${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}Проверка завершена.${NC}"
}

# --- НОВАЯ ФУНКЦИЯ: ТЕСТ СКОРОСТИ СЕРВЕРА ---
run_benchmark() {
    echo -e "${BLUE}=== ТЕСТ СКОРОСТИ СЕРВЕРА ===${NC}"
    echo ""
    echo -e "${YELLOW}Запуск теста производительности сервера...${NC}"
    echo -e "${CYAN}Тест включает:${NC}"
    echo "  • Процессор (CPU)"
    echo "  • Оперативная память (RAM)"
    echo "  • Скорость диска (I/O)"
    echo "  • Скорость сети (Download/Upload)"
    echo ""
    echo -e "${YELLOW}Время выполнения: ~2-5 минут${NC}"
    echo -e "${RED}⚠️  Тест может создать высокую нагрузку на сервер!${NC}"
    echo ""
    echo -n "Продолжить? (y/N): "
    read bench_choice
    
    if [[ ! "$bench_choice" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Тест отменен.${NC}"
        return
    fi
    
    echo ""
    echo -e "${BLUE}Начинаем тестирование...${NC}"
    echo -e "${GREEN}Результаты будут показаны ниже:${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # Проверяем наличие wget
    if ! command -v wget &> /dev/null; then
        echo -e "${YELLOW}Устанавливаем wget...${NC}"
        apt-get install -y wget > /dev/null 2>&1
    fi
    
    # Запускаем тест
    wget -qO- bench.tlab.pw | bash
    
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}Тест завершен!${NC}"
    echo ""
    
    # Предложение сохранить результат
    echo -n "Сохранить результат в файл? (y/N): "
    read save_result
    
    if [[ "$save_result" =~ ^[Yy]$ ]]; then
        RESULT_FILE="/root/benchmark-$(date +%Y%m%d_%H%M%S).txt"
        echo -e "${YELLOW}Результат будет сохранен в $RESULT_FILE${NC}"
        echo -e "${YELLOW}Чтобы сохранить результат, скопируйте вывод выше в файл вручную.${NC}"
        echo -e "${YELLOW}Или используйте: script -q -c 'wget -qO- bench.tlab.pw | bash' $RESULT_FILE${NC}"
        echo ""
        echo -n "Запустить тест с сохранением в файл? (y/N): "
        read save_run
        
        if [[ "$save_run" =~ ^[Yy]$ ]]; then
            script -q -c "wget -qO- bench.tlab.pw | bash" "$RESULT_FILE"
            echo -e "${GREEN}Результат сохранен в $RESULT_FILE${NC}"
        fi
    fi
}

# --- ФУНКЦИЯ НАСТРОЙКИ FIREWALL ---
configure_firewall() {
    echo -e "${BLUE}=== НАСТРОЙКА FIREWALL ===${NC}"
    echo ""
    
    # Проверяем наличие UFW
    if ! command -v ufw &> /dev/null; then
        echo -e "${YELLOW}UFW не установлен. Устанавливаем...${NC}"
        apt-get update -q
        apt-get install -y ufw
    fi
    
    echo -e "${YELLOW}Текущие правила UFW:${NC}"
    ufw status verbose
    echo ""
    
    echo -n "Настроить базовые правила для Remnawave Node? (y/N): "
    read fw_choice
    
    if [[ "$fw_choice" =~ ^[Yy]$ ]]; then
        # Предупреждение
        echo -e "${RED}⚠️ ВНИМАНИЕ! Это может отключить текущий доступ к серверу.${NC}"
        echo -e "${YELLOW}Убедитесь, что вы не потеряете SSH доступ!${NC}"
        echo -n "Продолжить? (y/N): "
        read confirm_fw
        
        if [[ ! "$confirm_fw" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Настройка firewall отменена.${NC}"
            return
        fi
        
        # Сброс к стандартным правилам
        echo -e "${BLUE}Сброс правил...${NC}"
        ufw --force reset
        
        # Базовые правила
        ufw default deny incoming
        ufw default allow outgoing
        
        # Разрешаем SSH (важно!)
        ufw allow ssh
        ufw allow 22/tcp
        
        # HTTP/HTTPS для домена
        ufw allow 80/tcp
        ufw allow 443/tcp
        
        # Порт для ноды
        if [ -n "$NODE_PORT" ]; then
            ufw allow $NODE_PORT/tcp
            echo -e "${GREEN}Разрешен порт ноды: $NODE_PORT${NC}"
        else
            echo -n "Введите порт ноды для разрешения (по умолчанию 2222): "
            read node_port_input
            NODE_PORT=${node_port_input:-2222}
            ufw allow $NODE_PORT/tcp
        fi
        
        # Включаем UFW
        echo -e "${YELLOW}Включение UFW...${NC}"
        ufw --force enable
        
        echo -e "${GREEN}Правила UFW применены:${NC}"
        ufw status verbose
        
        echo -e "${YELLOW}⚠️ Убедитесь, что SSH порт (22) открыт, иначе потеряете доступ!${NC}"
    else
        echo -e "${YELLOW}Настройка firewall пропущена.${NC}"
    fi
}

# --- ФУНКЦИЯ УДАЛЕНИЯ СКРИПТА ---
uninstall_script() {
    echo -e "${RED}=== УДАЛЕНИЕ СКРИПТА ===${NC}"
    echo -e "${YELLOW}ВНИМАНИЕ! Это удалит только сам скрипт.${NC}"
    echo -e "${YELLOW}Нода и настройки системы останутся нетронутыми.${NC}"
    echo ""
    echo -n "Вы уверены, что хотите удалить скрипт? (y/N): "
    read confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Удаление скрипта...${NC}"
        rm -f "$SCRIPT_PATH"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Скрипт успешно удален!${NC}"
            echo -e "${YELLOW}Для выхода нажмите Enter...${NC}"
            read
            exit 0
        else
            echo -e "${RED}✗ Ошибка при удалении скрипта.${NC}"
            echo -e "${YELLOW}Попробуйте удалить вручную: rm -f $SCRIPT_PATH${NC}"
        fi
    else
        echo -e "${GREEN}Удаление отменено.${NC}"
    fi
}

# --- ФУНКЦИЯ УСТАНОВКИ НОДЫ (БЕЗ ДОМЕНА) ---
install_node() {
    echo -e "${BLUE}=== УСТАНОВКА REMNAWAVE NODE ===${NC}"
    echo ""
    
    # Проверка системы перед установкой
    check_system
    echo ""
    read -n 1 -s -r -p "Нажмите любую клавишу для продолжения установки..."
    echo ""
    
    # Обновление
    echo -e "${BLUE}[1/4] Обновление системных пакетов...${NC}"
    apt-get update -q && apt-get upgrade -y -q
    apt-get install -y curl net-tools

    # Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${BLUE}[2/4] Docker не найден. Устанавливаем...${NC}"
        curl -fsSL https://get.docker.com | sh
        echo -e "${GREEN}Docker успешно установлен.${NC}"
    else
        echo -e "${GREEN}[2/4] Docker уже установлен.${NC}"
    fi

    echo ""
    echo -e "${YELLOW}--- Настройка ---${NC}"

    # Запрос данных
    while [[ -z "$SECRET_KEY" ]]; do
        echo -n "Введите SECRET_KEY (из панели Remnawave): "
        read SECRET_KEY
        if [[ -z "$SECRET_KEY" ]]; then
            echo -e "${RED}Secret Key обязателен!${NC}"
        fi
    done

    DEFAULT_PORT=2222
    echo -n "Введите порт узла (по умолчанию $DEFAULT_PORT): "
    read INPUT_PORT
    NODE_PORT=${INPUT_PORT:-$DEFAULT_PORT}

    # Установка ноды
    echo ""
    echo -e "${BLUE}[3/4] Настройка и запуск Remnawave Node...${NC}"

    INSTALL_DIR="/opt/remnanode"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    cat <<EOF > docker-compose.yml
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
EOF

    echo -e "${BLUE}[4/4] Запуск контейнера...${NC}"
    docker compose pull
    docker compose up -d

    if [ $? -eq 0 ]; then
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
        echo -e "${GREEN}>>> Узел успешно запущен на порту ${NODE_PORT}!${NC}"
        echo -e "${GREEN}>>> Для доступа к ноде используйте: http://${SERVER_IP}:${NODE_PORT}${NC}"
        echo -e "${YELLOW}>>> Не забудьте добавить узел в панели Remnawave!${NC}"
        echo -e "${YELLOW}>>> Secret Key: ${SECRET_KEY}${NC}"
    else
        echo -e "${RED}>>> Ошибка при запуске контейнера.${NC}"
        echo -e "${YELLOW}Проверьте логи: docker logs remnanode${NC}"
    fi
}

# --- ФУНКЦИЯ УСТАНОВКИ НОДЫ С ДОМЕНОМ ---
install_node_with_domain() {
    echo -e "${BLUE}=== УСТАНОВКА REMNAWAVE NODE С ДОМЕНОМ ===${NC}"
    echo ""
    
    # Запрос домена
    while [[ -z "$DOMAIN" ]]; do
        echo -n "Введите ваш домен (например, node.example.com): "
        read DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            echo -e "${RED}Домен обязателен!${NC}"
        fi
    done
    
    # Проверка DNS перед установкой
    echo -e "${YELLOW}Проверка DNS перед установкой...${NC}"
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
    
    if command -v dig &> /dev/null && [ -n "$SERVER_IP" ]; then
        DOMAIN_IP=$(dig +short $DOMAIN | head -1)
        
        if [ -n "$DOMAIN_IP" ]; then
            if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
                echo -e "${RED}⚠️ ВНИМАНИЕ! Домен $DOMAIN направлен на $DOMAIN_IP, а сервер имеет IP $SERVER_IP${NC}"
                echo -e "${YELLOW}SSL сертификат не сможет быть установлен!${NC}"
                echo -n "Продолжить установку? (y/N): "
                read continue_anyway
                if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                    echo -e "${RED}Установка отменена.${NC}"
                    return
                fi
                SSL_SKIP=true
            else
                echo -e "${GREEN}✓ DNS настроен корректно${NC}"
                SSL_SKIP=false
            fi
        else
            echo -e "${RED}✗ DNS запись для $DOMAIN не найдена!${NC}"
            echo -n "Продолжить установку без SSL? (y/N): "
            read continue_no_ssl
            if [[ ! "$continue_no_ssl" =~ ^[Yy]$ ]]; then
                echo -e "${RED}Установка отменена.${NC}"
                return
            fi
            SSL_SKIP=true
        fi
    else
        echo -e "${YELLOW}⚠ Не удалось проверить DNS (dig не установлен или нет интернета)${NC}"
        SSL_SKIP=false
    fi
    
    echo ""
    read -n 1 -s -r -p "Нажмите любую клавишу для продолжения установки..."
    echo ""
    
    # Обновление
    echo -e "${BLUE}[1/5] Обновление системных пакетов...${NC}"
    apt-get update -q && apt-get upgrade -y -q
    apt-get install -y curl git nginx certbot python3-certbot-nginx net-tools dnsutils

    # Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${BLUE}[2/5] Docker не найден. Устанавливаем...${NC}"
        curl -fsSL https://get.docker.com | sh
        echo -e "${GREEN}Docker успешно установлен.${NC}"
    else
        echo -e "${GREEN}[2/5] Docker уже установлен.${NC}"
    fi

    echo ""
    echo -e "${YELLOW}--- Настройка ---${NC}"

    # Запрос данных
    while [[ -z "$SECRET_KEY" ]]; do
        echo -n "Введите SECRET_KEY (из панели Remnawave): "
        read SECRET_KEY
        if [[ -z "$SECRET_KEY" ]]; then
            echo -e "${RED}Secret Key обязателен!${NC}"
        fi
    done

    DEFAULT_PORT=2222
    echo -n "Введите порт узла (по умолчанию $DEFAULT_PORT): "
    read INPUT_PORT
    NODE_PORT=${INPUT_PORT:-$DEFAULT_PORT}

    # Запрос email для SSL
    echo -n "Введите email для SSL сертификата (по умолчанию admin@$DOMAIN): "
    read SSL_EMAIL
    SSL_EMAIL=${SSL_EMAIL:-admin@$DOMAIN}

    # Настройка Nginx
    echo ""
    echo -e "${BLUE}[3/5] Настройка Nginx...${NC}"
    
    # Создаем директорию для сайта
    mkdir -p /var/www/$DOMAIN
    
    # Создаем страницу-заглушку в стиле Immich
    cat <<'EOF' > /var/www/$DOMAIN/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Immich - Вход</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .login-container {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            width: 100%;
            max-width: 400px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            animation: slideUp 0.6s ease-out;
        }
        @keyframes slideUp {
            from {
                opacity: 0;
                transform: translateY(30px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }
        .logo {
            text-align: center;
            margin-bottom: 30px;
        }
        .logo h1 {
            font-size: 32px;
            font-weight: 700;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        .logo p {
            color: #666;
            margin-top: 5px;
            font-size: 14px;
        }
        .form-group {
            margin-bottom: 20px;
        }
        .form-group label {
            display: block;
            margin-bottom: 5px;
            color: #333;
            font-weight: 500;
            font-size: 14px;
        }
        .form-group input {
            width: 100%;
            padding: 12px 15px;
            border: 2px solid #e0e0e0;
            border-radius: 10px;
            font-size: 14px;
            transition: all 0.3s;
            background: #f8f9fa;
        }
        .form-group input:focus {
            outline: none;
            border-color: #667eea;
            background: white;
            box-shadow: 0 0 0 4px rgba(102, 126, 234, 0.1);
        }
        .btn-login {
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
            margin-top: 10px;
        }
        .btn-login:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
        }
        .btn-login:active {
            transform: translateY(0);
        }
        .footer {
            text-align: center;
            margin-top: 20px;
            color: #999;
            font-size: 12px;
        }
        .demo-badge {
            display: inline-block;
            background: #f0f0f0;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 12px;
            color: #666;
            margin-top: 10px;
        }
        .status {
            text-align: center;
            margin-top: 15px;
            padding: 10px;
            border-radius: 8px;
            background: #f0f9ff;
            color: #0c5460;
            font-size: 13px;
            display: none;
        }
        .status.show {
            display: block;
            animation: fadeIn 0.5s;
        }
        @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
        }
        .status.error {
            background: #f8d7da;
            color: #721c24;
        }
        .status.success {
            background: #d4edda;
            color: #155724;
        }
    </style>
</head>
<body>
    <div class="login-container">
        <div class="logo">
            <h1>📸 Immich</h1>
            <p>Self-hosted photo management</p>
        </div>
        <form id="loginForm" onsubmit="return handleLogin(event)">
            <div class="form-group">
                <label for="email">Email</label>
                <input type="email" id="email" placeholder="user@example.com" value="email@immich.com" required>
            </div>
            <div class="form-group">
                <label for="password">Password</label>
                <input type="password" id="password" placeholder="••••••••" value="demo123" required>
            </div>
            <button type="submit" class="btn-login">Sign In</button>
        </form>
        <div id="status" class="status">Connecting to Immich server...</div>
        <div class="footer">
            <div class="demo-badge">🔒</div>
            <p style="margin-top: 10px;">Immich v3.0.1</p>
            <p style="margin-top: 5px; color: #ccc;">Powered by Immich</p>
        </div>
    </div>

    <script>
        function handleLogin(e) {
            e.preventDefault();
            const status = document.getElementById('status');
            const email = document.getElementById('email').value;
            const password = document.getElementById('password').value;
            
            status.className = 'status show';
            status.textContent = '🔍 Connecting to Immich server...';
            
            // Имитация проверки
            setTimeout(() => {
                if (email && password) {
                    status.className = 'status show success';
                    status.textContent = '✅ Connection successful! Welcome to Immich!';
                } else {
                    status.className = 'status show error';
                    status.textContent = '❌ Please enter email and password.';
                }
            }, 1500);
            
            return false;
        }
    </script>
</body>
</html>
EOF

    # Настройка Nginx
    cat <<EOF > /etc/nginx/sites-available/$DOMAIN
server {
    listen 80;
    server_name $DOMAIN;
    
    root /var/www/$DOMAIN;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;
}
EOF

    # Активируем сайт
    ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx

    echo -e "${GREEN}Nginx настроен для домена $DOMAIN${NC}"

    # SSL сертификат
    echo ""
    echo -e "${BLUE}[4/5] Настройка SSL сертификата...${NC}"
    
    if [[ "$SSL_SKIP" != true ]]; then
        echo -e "${YELLOW}Убедитесь, что домен $DOMAIN направлен на этот сервер!${NC}"
        echo -n "Хотите установить SSL сертификат Let's Encrypt? (y/N): "
        read ssl_choice
        
        if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
            # Проверка порта 80
            if ! nc -z localhost 80 2>/dev/null; then
                echo -e "${YELLOW}⚠️ Порт 80 не открыт! Убедитесь, что firewall разрешает 80 порт.${NC}"
                echo -n "Попробовать открыть порт 80 автоматически? (y/N): "
                read auto_fix
                if [[ "$auto_fix" =~ ^[Yy]$ ]]; then
                    if command -v ufw &> /dev/null; then
                        ufw allow 80/tcp
                        ufw allow 443/tcp
                    else
                        iptables -A INPUT -p tcp --dport 80 -j ACCEPT
                        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
                    fi
                    echo -e "${GREEN}Порты 80 и 443 открыты.${NC}"
                fi
            fi
            
            certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}SSL сертификат успешно установлен!${NC}"
                # Обновляем конфиг Nginx для HTTPS
                cat <<EOF > /etc/nginx/sites-available/$DOMAIN
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    root /var/www/$DOMAIN;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    access_log /var/log/nginx/${DOMAIN}_access.log;
    error_log /var/log/nginx/${DOMAIN}_error.log;
}
EOF
                systemctl reload nginx
                echo -e "${GREEN}HTTPS настроен для $DOMAIN${NC}"
            else
                echo -e "${RED}Ошибка установки SSL сертификата.${NC}"
                echo -e "${YELLOW}Проверьте, что домен доступен из интернета и порт 80 открыт.${NC}"
            fi
        else
            echo -e "${YELLOW}SSL сертификат не установлен.${NC}"
        fi
    else
        echo -e "${YELLOW}SSL сертификат пропущен из-за проблем с DNS.${NC}"
        echo -e "${YELLOW}Вы можете установить его позже командой: certbot --nginx -d $DOMAIN${NC}"
    fi

    # Установка ноды
    echo ""
    echo -e "${BLUE}[5/5] Настройка и запуск Remnawave Node...${NC}"

    INSTALL_DIR="/opt/remnanode"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    cat <<EOF > docker-compose.yml
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
EOF

    docker compose pull
    docker compose up -d

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}>>> Узел успешно запущен на порту ${NODE_PORT}!${NC}"
        if [[ "$ssl_choice" =~ ^[Yy]$ ]] && [ $? -eq 0 ]; then
            echo -e "${GREEN}>>> Сайт-заглушка доступен по адресу: https://$DOMAIN${NC}"
        else
            echo -e "${GREEN}>>> Сайт-заглушка доступен по адресу: http://$DOMAIN${NC}"
        fi
        echo -e "${GREEN}>>> Для доступа к ноде используйте: http://$DOMAIN:$NODE_PORT${NC}"
        echo -e "${YELLOW}>>> Secret Key: ${SECRET_KEY}${NC}"
        
        echo ""
        echo -e "${CYAN}=== ИНФОРМАЦИЯ О САЙТЕ ===${NC}"
        echo -e "Домен: $DOMAIN"
        echo -e "Путь: /var/www/$DOMAIN"
        echo -e "Страница: http://$DOMAIN"
        echo -e "Логи Nginx: /var/log/nginx/${DOMAIN}_access.log"
        echo -e "${CYAN}===========================${NC}"
    else
        echo -e "${RED}>>> Ошибка при запуске контейнера.${NC}"
        echo -e "${YELLOW}Проверьте логи: docker logs remnanode${NC}"
    fi
}

# --- ФУНКЦИЯ ОПТИМИЗАЦИИ СЕТИ ---
apply_optimizations() {
    echo -e "${BLUE}=== ПРИМЕНЕНИЕ СЕТЕВЫХ НАСТРОЕК (SYSCTL) ===${NC}"
    echo ""
    
    # Проверка поддержки BBR
    echo -e "${YELLOW}Проверка поддержки BBR...${NC}"
    if ! modprobe tcp_bbr 2>/dev/null; then
        echo -e "${YELLOW}Предупреждение: Ваше ядро может не поддерживать BBR.${NC}"
        echo -e "${YELLOW}Рекомендуется ядро 4.9+ для полной оптимизации.${NC}"
        echo -n "Продолжить применение настроек? (y/N): "
        read continue_tuning
        if [[ ! "$continue_tuning" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Оптимизация отменена.${NC}"
            return
        fi
    else
        echo -e "${GREEN}BBR поддерживается.${NC}"
    fi
    
    echo -e "${YELLOW}Применяются параметры: BBR, TCP FastOpen, Tweaks, IPv6 Disable...${NC}"
    
    # Бэкап существующих настроек
    if [ -f /etc/sysctl.d/99-remnawave-tuning.conf ]; then
        cp /etc/sysctl.d/99-remnawave-tuning.conf /etc/sysctl.d/99-remnawave-tuning.conf.bak.$(date +%Y%m%d_%H%M%S)
        echo -e "${YELLOW}Создан бэкап существующих настроек.${NC}"
    fi
    
    cat <<EOF > /etc/sysctl.d/99-remnawave-tuning.conf
# === 1. IPv6 (Отключен для стабильности) ===
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# === 2. IPv4 и Маршрутизация ===
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# === 3. Оптимизация TCP и BBR ===
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192

# Keepalive
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fin_timeout = 15

# Буферы
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# === 4. Безопасность и Лимиты ===
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.tcp_syncookies = 1
fs.file-max = 2097152
vm.swappiness = 10
vm.overcommit_memory = 1
EOF

    echo -e "${BLUE}Применяем настройки...${NC}"
    sysctl --system > /dev/null 2>&1
    
    echo -e "${GREEN}>>> Настройки успешно применены!${NC}"
    
    # Проверка применения
    echo ""
    echo -e "${CYAN}=== ПРОВЕРКА НАСТРОЕК ===${NC}"
    echo -n "BBR: "
    sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}' || echo "Не поддерживается"
    echo -n "TCP FastOpen: "
    sysctl net.ipv4.tcp_fastopen 2>/dev/null | awk '{print $3}' || echo "Не поддерживается"
    echo -n "IPv6: "
    sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | awk '{print $3}' || echo "Не поддерживается"
    echo -n "Swappiness: "
    sysctl vm.swappiness 2>/dev/null | awk '{print $3}' || echo "Не поддерживается"
}

# --- ФУНКЦИЯ УПРАВЛЕНИЯ НОДОЙ ---
manage_node() {
    echo -e "${BLUE}=== УПРАВЛЕНИЕ REMNAWAVE NODE ===${NC}"
    echo ""
    
    if ! docker ps 2>/dev/null | grep -q remnanode; then
        echo -e "${RED}Контейнер remnanode не найден или не запущен.${NC}"
        echo -e "${YELLOW}Проверьте, установлена ли нода.${NC}"
        return
    fi
    
    echo -e "${GREEN}Выберите действие:${NC}"
    echo "1) Показать логи (последние 50 строк)"
    echo "2) Показать логи в реальном времени"
    echo "3) Перезапустить ноду"
    echo "4) Остановить ноду"
    echo "5) Обновить ноду"
    echo "6) Показать статус"
    echo "7) Назад"
    echo ""
    echo -n "Ваш выбор: "
    read manage_choice
    
    case $manage_choice in
        1)
            docker logs --tail=50 remnanode
            ;;
        2)
            echo -e "${YELLOW}Нажмите Ctrl+C для выхода из логов...${NC}"
            sleep 2
            docker logs -f remnanode
            ;;
        3)
            if [ -f /opt/remnanode/docker-compose.yml ]; then
                docker compose -f /opt/remnanode/docker-compose.yml restart
                echo -e "${GREEN}Нода перезапущена.${NC}"
            else
                docker restart remnanode
                echo -e "${GREEN}Нода перезапущена.${NC}"
            fi
            ;;
        4)
            if [ -f /opt/remnanode/docker-compose.yml ]; then
                docker compose -f /opt/remnanode/docker-compose.yml stop
            else
                docker stop remnanode
            fi
            echo -e "${YELLOW}Нода остановлена.${NC}"
            ;;
        5)
            if [ -f /opt/remnanode/docker-compose.yml ]; then
                cd /opt/remnanode
                docker compose pull
                docker compose up -d
            else
                docker pull remnawave/node:latest
                docker restart remnanode
            fi
            echo -e "${GREEN}Нода обновлена.${NC}"
            ;;
        6)
            docker ps --filter "name=remnanode" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            echo ""
            echo -e "${CYAN}Информация о контейнере:${NC}"
            docker inspect remnanode --format='{{.Config.Image}}' | sed 's/^/  Образ: /'
            docker inspect remnanode --format='{{.State.StartedAt}}' | sed 's/^/  Запущен: /'
            ;;
        7)
            return
            ;;
        *)
            echo -e "${RED}Неверный выбор.${NC}"
            ;;
    esac
}

# --- ФУНКЦИЯ СТАТУСА ---
check_status() {
    echo -e "${BLUE}=== СТАТУС REMNAWAVE NODE ===${NC}"
    echo ""
    
    # Проверка ноды
    echo -e "${CYAN}=== Нода ===${NC}"
    if docker ps 2>/dev/null | grep -q remnanode; then
        echo -e "${GREEN}✓ Нода запущена${NC}"
        docker ps --filter "name=remnanode" --format "  Статус: {{.Status}}"
        docker ps --filter "name=remnanode" --format "  Образ: {{.Image}}"
        
        # Получаем порт из переменных окружения
        NODE_PORT=$(docker inspect remnanode 2>/dev/null | grep -A10 "Env" | grep NODE_PORT | cut -d'=' -f2 | tr -d '"' | head -1)
        if [ -n "$NODE_PORT" ]; then
            echo -e "  Порт: ${GREEN}$NODE_PORT${NC}"
        fi
        
        # Проверка работы
        if [ -n "$NODE_PORT" ]; then
            echo -n "  Проверка доступности: "
            if nc -z localhost $NODE_PORT 2>/dev/null; then
                echo -e "${GREEN}✓ Порт $NODE_PORT доступен${NC}"
            else
                echo -e "${RED}✗ Порт $NODE_PORT недоступен${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ Нода не запущена${NC}"
    fi
    
    # Сетевые настройки
    echo ""
    echo -e "${CYAN}=== СЕТЕВЫЕ НАСТРОЙКИ ===${NC}"
    echo -n "BBR: "
    bbr_status=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    if [ "$bbr_status" = "bbr" ]; then
        echo -e "${GREEN}Активен${NC}"
    else
        echo -e "${RED}Не активен (текущий: $bbr_status)${NC}"
    fi
    
    echo -n "TCP FastOpen: "
    fastopen=$(sysctl net.ipv4.tcp_fastopen 2>/dev/null | awk '{print $3}')
    if [ "$fastopen" = "3" ]; then
        echo -e "${GREEN}Активен${NC}"
    else
        echo -e "${YELLOW}Не активен (текущий: $fastopen)${NC}"
    fi
    
    echo -n "IPv6: "
    ipv6_status=$(sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | awk '{print $3}')
    if [ "$ipv6_status" = "1" ]; then
        echo -e "${YELLOW}Отключен${NC}"
    else
        echo -e "${GREEN}Включен${NC}"
    fi
    
    # Nginx
    echo ""
    echo -e "${CYAN}=== Nginx ===${NC}"
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo -e "${GREEN}✓ Nginx активен${NC}"
        echo "  Активные сайты:"
        ls -la /etc/nginx/sites-enabled/ 2>/dev/null | grep -v total | awk '{print "    - " $9}'
    else
        echo -e "${YELLOW}⚠ Nginx не активен${NC}"
    fi
    
    # Docker
    echo ""
    echo -e "${CYAN}=== Docker ===${NC}"
    if command -v docker &> /dev/null; then
        docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        echo -e "  Версия: $docker_version"
        echo -n "  Контейнеров запущено: "
        docker ps -q 2>/dev/null | wc -l
    fi
    
    # Система
    echo ""
    echo -e "${CYAN}=== СИСТЕМА ===${NC}"
    echo -e "  Загрузка CPU: $(top -bn1 | head -5 | awk '/Cpu/ {print $2}')%"
    echo -e "  Использование RAM: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
    echo -e "  Диск: $(df -h / | awk 'NR==2 {print $5 " (" $3 "/" $2 ")"}')"
    echo -e "  Время работы: $(uptime -p | sed 's/up //')"
}

# --- ФУНКЦИЯ БЭКАПА ---
backup_configs() {
    echo -e "${BLUE}=== СОЗДАНИЕ БЭКАПА ===${NC}"
    echo ""
    
    BACKUP_DIR="/root/backups/remnawave-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    echo -e "${YELLOW}Создание бэкапа в $BACKUP_DIR...${NC}"
    
    # Бэкап ноды
    if [ -d /opt/remnanode ]; then
        cp -r /opt/remnanode "$BACKUP_DIR/"
        echo -e "${GREEN}✓ Конфиги ноды сохранены${NC}"
    fi
    
    # Бэкап Nginx
    if [ -d /etc/nginx/sites-available ]; then
        cp -r /etc/nginx/sites-available "$BACKUP_DIR/"
        echo -e "${GREEN}✓ Конфиги Nginx сохранены${NC}"
    fi
    
    # Бэкап sysctl
    if [ -f /etc/sysctl.d/99-remnawave-tuning.conf ]; then
        cp /etc/sysctl.d/99-remnawave-tuning.conf "$BACKUP_DIR/"
        echo -e "${GREEN}✓ Настройки sysctl сохранены${NC}"
    fi
    
    # Информация
    echo ""
    echo -e "${GREEN}Бэкап создан в $BACKUP_DIR${NC}"
    echo -e "${YELLOW}Размер: $(du -sh $BACKUP_DIR | cut -f1)${NC}"
    
    # Создание архива
    echo -n "Создать архив для скачивания? (y/N): "
    read archive_choice
    if [[ "$archive_choice" =~ ^[Yy]$ ]]; then
        cd /root/backups
        tar -czf "remnawave-backup-$(date +%Y%m%d).tar.gz" "$(basename "$BACKUP_DIR")"
        echo -e "${GREEN}Архив создан: /root/backups/remnawave-backup-$(date +%Y%m%d).tar.gz${NC}"
    fi
}

# --- ГЛАВНЫЙ ЦИКЛ МЕНЮ ---
while true; do
    show_banner
    echo -e "${GREEN}Выберите действие:${NC}"
    echo "1) Установить Remnawave Node (стандартная)"
    echo "2) Установить Node с доменом и сайтом-заглушкой"
    echo "3) Применить сетевые настройки (BBR + Оптимизация)"
    echo "4) Настроить Firewall (UFW)"
    echo "5) Проверить систему (ядро, DNS, порты)"
    echo "6) Управление нодой (логи, обновления, перезапуск)"
    echo "7) Статус и информация"
    echo "8) Создать бэкап конфигов"
    echo "9) 🚀 Тест скорости сервера (benchmark)"
    echo "10) 🗑️  Удалить этот скрипт"
    echo "11) Выход"
    echo ""
    echo -n "Ваш выбор: "
    read choice

    case $choice in
        1)
            install_node
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        2)
            install_node_with_domain
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        3)
            apply_optimizations
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        4)
            configure_firewall
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        5)
            check_system
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        6)
            manage_node
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        7)
            check_status
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        8)
            backup_configs
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        9)
            run_benchmark
            echo ""
            read -n 1 -s -r -p "Нажмите любую клавишу, чтобы вернуться в меню..."
            ;;
        10)
            uninstall_script
            ;;
        11)
            echo -e "${YELLOW}Выход.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор.${NC}"
            sleep 1
            ;;
    esac
done
