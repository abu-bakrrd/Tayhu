#!/bin/bash

# ============================================================================
# ПОЛНЫЙ АВТОМАТИЧЕСКИЙ МАСТЕР-СКРИПТ РАЗВЕРТЫВАНИЯ
# Устанавливает ВСЕ: Shop App + AI Bot + Telegram Bot + Домен + SSL
# ============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции для вывода
print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# ============================================================================
# ПРИВЕТСТВИЕ И ПОДТВЕРЖДЕНИЕ
# ============================================================================
clear
echo -e "${BLUE}================================================================${NC}"
echo -e "${GREEN}       🚀 МАСТЕР-СКРИПТ ПОЛНОГО РАЗВЕРТЫВАНИЯ VPS 🚀${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""
echo "Этот скрипт автоматически установит и настроит:"
echo ""
echo "  📦 Системные пакеты:"
echo "     • Python 3, PostgreSQL, Nginx, Node.js"
echo "     • Certbot (для SSL)"
echo "     • Git, Curl и другие утилиты"
echo ""
echo "  🌐 Web приложение (Магазин):"
echo "     • Flask Backend + React Frontend"
echo "     • Gunicorn сервер"
echo ""
echo "  🤖 Боты:"
echo "     • AI Bot 'Mona' (клиентская поддержка)"
echo "     • Telegram Bot (основной бот магазина)"
echo ""
echo "  🗄️ База данных:"
echo "     • PostgreSQL настройка"
echo "     • Автоматическая инициализация таблиц"
echo ""
echo "  🔒 Безопасность:"
echo "     • SSL сертификаты (Let's Encrypt)"
echo "     • HTTPS редирект"
echo "     • Firewall настройка"
echo ""
echo -e "${YELLOW}⚠️  ВАЖНО: Скрипт должен запускаться на чистом VPS Ubuntu 20.04/22.04${NC}"
echo ""
read -p "Продолжить установку? (y/n): " CONFIRM_INSTALL
if [[ "$CONFIRM_INSTALL" != "y" && "$CONFIRM_INSTALL" != "Y" ]]; then
    echo -e "${RED}❌ Установка отменена.${NC}"
    exit 0
fi

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    print_error "Запустите скрипт с правами root: sudo bash master_deploy.sh"
    exit 1
fi

# ============================================================================
# СБОР ПАРАМЕТРОВ КОНФИГУРАЦИИ
# ============================================================================
echo ""
echo -e "${BLUE}================================================================${NC}"
echo -e "${GREEN}       📝 НАСТРОЙКА ПАРАМЕТРОВ${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# GitHub репозиторий
echo -e "${YELLOW}🔗 ИСТОЧНИК КОДА${NC}"
read -p "GitHub репозиторий (оставьте пустым для локальных файлов): " GITHUB_REPO
if [ ! -z "$GITHUB_REPO" ]; then
    read -p "Ветка [main]: " GIT_BRANCH
    GIT_BRANCH=${GIT_BRANCH:-main}
fi
echo ""

# Системные параметры
echo -e "${YELLOW}⚙️  СИСТЕМНЫЕ НАСТРОЙКИ${NC}"
read -p "Имя пользователя приложения [shopapp]: " APP_USER
APP_USER=${APP_USER:-shopapp}

read -p "Имя базы данных [shop_db]: " DB_NAME
DB_NAME=${DB_NAME:-shop_db}

read -p "Пользователь БД [shop_user]: " DB_USER
DB_USER=${DB_USER:-shop_user}

read -sp "Пароль БД: " DB_PASSWORD
echo
while [ -z "$DB_PASSWORD" ]; do
    print_error "Пароль не может быть пустым!"
    read -sp "Пароль БД: " DB_PASSWORD
    echo
done

read -p "Порт приложения [5000]: " APP_PORT
APP_PORT=${APP_PORT:-5000}
echo ""

# Telegram Bot токены
echo -e "${YELLOW}🤖 ТОКЕНЫ TELEGRAM БОТОВ${NC}"
read -p "AI Bot Token (Mona): " AI_BOT_TOKEN
read -p "Main Telegram Bot Token: " TELEGRAM_BOT_TOKEN
echo ""

# API ключи
echo -e "${YELLOW}🔑 API КЛЮЧИ${NC}"
read -p "GROQ API Key (для AI): " GROQ_API_KEY
read -p "GEMINI API Key (опционально): " GEMINI_API_KEY
read -p "Cloudinary Cloud Name (опционально): " CLOUDINARY_CLOUD_NAME
read -p "Cloudinary API Key (опционально): " CLOUDINARY_API_KEY
read -p "Cloudinary API Secret (опционально): " CLOUDINARY_API_SECRET
echo ""

# Домен и SSL
echo -e "${YELLOW}🌐 ДОМЕН И SSL${NC}"
read -p "Ваш домен (например: myshop.com, оставьте пустым чтобы пропустить): " DOMAIN
if [ ! -z "$DOMAIN" ]; then
    read -p "Email для SSL уведомлений: " SSL_EMAIL
fi
echo ""

print_step "Параметры сохранены. Начинаем установку..."
sleep 2

# ============================================================================
# УСТАНОВКА СИСТЕМНЫХ ПАКЕТОВ
# ============================================================================
echo ""
print_step "Обновление системы..."
apt update && apt upgrade -y

print_step "Установка основных пакетов..."
apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    postgresql \
    postgresql-contrib \
    nginx \
    git \
    curl \
    ufw \
    certbot \
    python3-certbot-nginx \
    build-essential

# Node.js
if ! command -v node &> /dev/null; then
    print_step "Установка Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt install -y nodejs
else
    print_info "Node.js уже установлен: $(node --version)"
fi

# ============================================================================
# СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
# ============================================================================
print_step "Создание пользователя: $APP_USER"
if id "$APP_USER" &>/dev/null; then
    print_warning "Пользователь $APP_USER уже существует"
else
    adduser --disabled-password --gecos "" --quiet $APP_USER 2>/dev/null || \
    useradd -m -s /bin/bash $APP_USER
    print_step "Пользователь $APP_USER создан"
fi

usermod -a -G www-data $APP_USER

# ============================================================================
# НАСТРОЙКА POSTGRESQL
# ============================================================================
print_step "Настройка PostgreSQL..."
sudo -u postgres psql <<EOF
SELECT 'CREATE DATABASE $DB_NAME' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\\gexec
DO
\$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '$DB_USER') THEN
      CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
   END IF;
END
\$\$;
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
ALTER DATABASE $DB_NAME OWNER TO $DB_USER;
EOF

# Настройка pg_hba.conf
PG_VERSION=$(ls /etc/postgresql/)
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
if ! grep -q "host.*all.*all.*127.0.0.1/32.*md5" "$PG_HBA"; then
    echo "host    all             all             127.0.0.1/32            md5" >> "$PG_HBA"
    systemctl restart postgresql
fi

print_step "PostgreSQL настроен"

# ============================================================================
# ПОЛУЧЕНИЕ КОДА ПРИЛОЖЕНИЯ
# ============================================================================
APP_DIR="/home/$APP_USER/app"

if [ ! -z "$GITHUB_REPO" ]; then
    print_step "Клонирование из GitHub: $GITHUB_REPO"
    if [ -d "$APP_DIR" ]; then
        rm -rf $APP_DIR
    fi
    sudo -u $APP_USER git clone -b $GIT_BRANCH $GITHUB_REPO $APP_DIR
else
    print_step "Копирование локальных файлов..."
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    mkdir -p $APP_DIR
    cp -r $SCRIPT_DIR/../* $APP_DIR/ 2>/dev/null || true
    chown -R $APP_USER:$APP_USER $APP_DIR
fi

# ============================================================================
# СОЗДАНИЕ .ENV ФАЙЛА
# ============================================================================
print_step "Создание .env файла..."
SESSION_SECRET=$(openssl rand -hex 32)
cat > $APP_DIR/.env <<EOF
# Database
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME

# Flask
PORT=$APP_PORT
FLASK_ENV=production
SESSION_SECRET=$SESSION_SECRET

# AI Bot
AI_BOT_TOKEN=$AI_BOT_TOKEN
GROQ_API_KEY=$GROQ_API_KEY
GEMINI_API_KEY=$GEMINI_API_KEY

# Main Telegram Bot
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN

# Cloudinary
CLOUDINARY_CLOUD_NAME=$CLOUDINARY_CLOUD_NAME
CLOUDINARY_API_KEY=$CLOUDINARY_API_KEY
CLOUDINARY_API_SECRET=$CLOUDINARY_API_SECRET
EOF

chown $APP_USER:$APP_USER $APP_DIR/.env
chmod 600 $APP_DIR/.env

# ============================================================================
# УСТАНОВКА ЗАВИСИМОСТЕЙ
# ============================================================================
print_step "Установка зависимостей..."
cd $APP_DIR

# Frontend
sudo -u $APP_USER bash <<EOF
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd $APP_DIR
if [ -f "package.json" ]; then
    npm install
    npm run build
fi
EOF

# Backend (Python)
sudo -u $APP_USER bash <<EOF
cd $APP_DIR
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
EOF

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ БАЗЫ ДАННЫХ
# ============================================================================
print_step "Инициализация таблиц базы данных..."
sudo -u $APP_USER bash <<EOF
cd $APP_DIR
source venv/bin/activate
python3 scripts/init_tables.py
python3 scripts/seed_db.py
EOF

# ============================================================================
# НАСТРОЙКА ПРАВ
# ============================================================================
chmod 755 /home/$APP_USER
chmod 755 $APP_DIR
if [ -d "$APP_DIR/dist" ]; then
    chown -R $APP_USER:www-data $APP_DIR/dist
    chmod -R 755 $APP_DIR/dist
fi

# ============================================================================
# СОЗДАНИЕ SYSTEMD СЕРВИСОВ
# ============================================================================
print_step "Создание systemd сервисов..."

# Flask App (Shop)
cat > /etc/systemd/system/shop-app.service <<EOF
[Unit]
Description=Telegram Shop Flask Application
After=network.target postgresql.service

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/gunicorn app:app --bind 127.0.0.1:$APP_PORT --workers 4 --timeout 120
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# AI Bot (Mona)
cat > /etc/systemd/system/ai-bot.service <<EOF
[Unit]
Description=AI Customer Support Bot (Mona)
After=network.target postgresql.service shop-app.service

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/python3 ai_bot/ai_customer_bot.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Main Telegram Bot
if [ ! -z "$TELEGRAM_BOT_TOKEN" ]; then
cat > /etc/systemd/system/telegram-bot.service <<EOF
[Unit]
Description=Main Telegram Shop Bot
After=network.target postgresql.service shop-app.service

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR/telegram_bot
Environment="PATH=$APP_DIR/venv/bin"
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/python3 telegrambot.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
fi

# ============================================================================
# ЗАПУСК СЕРВИСОВ
# ============================================================================
print_step "Запуск сервисов..."
systemctl daemon-reload

systemctl enable shop-app
systemctl start shop-app

systemctl enable ai-bot
systemctl start ai-bot

if [ ! -z "$TELEGRAM_BOT_TOKEN" ]; then
    systemctl enable telegram-bot
    systemctl start telegram-bot
fi

sleep 3

# Проверка статуса сервисов
echo ""
print_info "Проверка статуса сервисов..."
if systemctl is-active --quiet shop-app; then
    print_step "✅ Shop App запущен"
else
    print_error "❌ Shop App не запустился"
fi

if systemctl is-active --quiet ai-bot; then
    print_step "✅ AI Bot запущен"
else
    print_error "❌ AI Bot не запустился"
fi

if [ ! -z "$TELEGRAM_BOT_TOKEN" ]; then
    if systemctl is-active --quiet telegram-bot; then
        print_step "✅ Telegram Bot запущен"
    else
        print_error "❌ Telegram Bot не запустился"
    fi
fi

# ============================================================================
# НАСТРОЙКА NGINX
# ============================================================================
print_step "Настройка Nginx..."

if [ ! -z "$DOMAIN" ]; then
    # С доменом
    cat > /etc/nginx/sites-available/shop <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    client_max_body_size 20M;

    access_log /var/log/nginx/shop_access.log;
    error_log /var/log/nginx/shop_error.log;

    location /assets {
        alias $APP_DIR/dist/public/assets;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location /config {
        alias $APP_DIR/config;
        expires 1h;
        add_header Cache-Control "public";
    }

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
else
    # Без домена (только IP)
    cat > /etc/nginx/sites-available/shop <<EOF
server {
    listen 80;
    server_name _;
    client_max_body_size 20M;

    access_log /var/log/nginx/shop_access.log;
    error_log /var/log/nginx/shop_error.log;

    location /assets {
        alias $APP_DIR/dist/public/assets;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location /config {
        alias $APP_DIR/config;
        expires 1h;
        add_header Cache-Control "public";
    }

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
fi

ln -sf /etc/nginx/sites-available/shop /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

if nginx -t; then
    systemctl restart nginx
    print_step "Nginx настроен и запущен"
else
    print_error "Ошибка конфигурации Nginx!"
fi

# ============================================================================
# НАСТРОЙКА FIREWALL
# ============================================================================
print_step "Настройка Firewall (UFW)..."
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
print_step "Firewall настроен"

# ============================================================================
# SSL СЕРТИФИКАТ (ОПЦИОНАЛЬНО)
# ============================================================================
if [ ! -z "$DOMAIN" ] && [ ! -z "$SSL_EMAIL" ]; then
    echo ""
    print_step "Установка SSL сертификата..."
    
    # Проверка DNS
    print_info "Проверка DNS для $DOMAIN..."
    if host $DOMAIN > /dev/null 2>&1; then
        print_step "DNS резолвится корректно"
        
        # Получение SSL
        certbot --nginx -d $DOMAIN -d www.$DOMAIN \
            --non-interactive \
            --agree-tos \
            --email $SSL_EMAIL \
            --redirect
        
        if [ $? -eq 0 ]; then
            print_step "✅ SSL сертификат установлен!"
        else
            print_warning "⚠️  SSL установка не удалась. Можно попробовать позже вручную."
        fi
    else
        print_warning "⚠️  DNS не резолвится. Пропускаем SSL. Настройте DNS и запустите: sudo certbot --nginx"
    fi
fi

# ============================================================================
# ФИНАЛЬНАЯ ИНФОРМАЦИЯ
# ============================================================================
clear
echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}       ✅ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА! ✅${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""

SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${BLUE}📱 ДОСТУП К ПРИЛОЖЕНИЮ:${NC}"
if [ ! -z "$DOMAIN" ]; then
    if [ ! -z "$SSL_EMAIL" ]; then
        echo -e "   🌐 URL: ${GREEN}https://$DOMAIN${NC}"
        echo -e "   🌐 Альт: ${GREEN}https://www.$DOMAIN${NC}"
    else
        echo -e "   🌐 URL: ${GREEN}http://$DOMAIN${NC}"
        echo -e "   (Установите SSL: sudo certbot --nginx)"
    fi
else
    echo -e "   🌐 URL: ${GREEN}http://$SERVER_IP${NC}"
fi
echo ""

echo -e "${BLUE}🤖 БОТЫ (Telegram):${NC}"
echo -e "   ✅ AI Bot (Mona) - запущен"
if [ ! -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "   ✅ Main Telegram Bot - запущен"
fi
echo ""

echo -e "${BLUE}📊 УПРАВЛЕНИЕ СЕРВИСАМИ:${NC}"
echo -e "   Shop App:      sudo systemctl {start|stop|restart|status} shop-app"
echo -e "   AI Bot:        sudo systemctl {start|stop|restart|status} ai-bot"
if [ ! -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "   Telegram Bot:  sudo systemctl {start|stop|restart|status} telegram-bot"
fi
echo ""

echo -e "${BLUE}📜 ПРОСМОТР ЛОГОВ:${NC}"
echo -e "   Shop App:      sudo journalctl -u shop-app -f"
echo -e "   AI Bot:        sudo journalctl -u ai-bot -f"
if [ ! -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "   Telegram Bot:  sudo journalctl -u telegram-bot -f"
fi
echo ""

echo -e "${BLUE}🔄 ОБНОВЛЕНИЕ:${NC}"
echo -e "   cd $APP_DIR && git pull"
echo -e "   sudo systemctl restart shop-app ai-bot telegram-bot"
echo ""

echo -e "${YELLOW}📝 СЛЕДУЮЩИЕ ШАГИ:${NC}"
echo -e "   1. Проверьте работу сайта: $(if [ ! -z \"$DOMAIN\" ]; then echo \"https://$DOMAIN\"; else echo \"http://$SERVER_IP\"; fi)"
echo -e "   2. Настройте webhook для ботов (если требуется)"
echo -e "   3. Обновите BotFather с URL вашего магазина"
echo -e "   4. Проверьте логи всех сервисов на ошибки"
echo ""

echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}       🎉 ВСЕ ГОТОВО! ПРИЯТНОЙ РАБОТЫ! 🎉${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""
