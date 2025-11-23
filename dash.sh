#!/bin/bash

# ========== AUTO CTRLPANEL INSTALLER ==========
# Values filled automatically by Telegram Bot

DOMAIN="{{DOMAIN}}"
DB_PASSWORD="{{DB_PASSWORD}}"

DB_USER="ctrlpaneluser"
DB_NAME="ctrlpanel"
INSTALL_DIR="/var/www/ctrlpanel"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[1] بدء تثبيت CtrlPanel...${NC}"

# ------------ CHECK ROOT ------------
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}[!] SUDO MODE ENABLED${NC}"
    SUDO="sudo"
else
    SUDO=""
fi

# ------------ CHECK OS ------------
if [ ! -f /etc/debian_version ]; then
    echo -e "${RED}[خطأ] النظام غير مدعوم (Debian/Ubuntu فقط)${NC}"
    exit 1
fi

echo -e "${GREEN}[2] تحديث النظام...${NC}"
$SUDO apt update -y && $SUDO apt upgrade -y

echo -e "${GREEN}[3] تثبيت التبعيات...${NC}"
$SUDO apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release

echo -e "${GREEN}[4] إعداد مستودعات PHP و Redis...${NC}"
$SUDO wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | $SUDO tee /etc/apt/sources.list.d/php.list

curl -fsSL https://packages.redis.io/gpg | gpg --dearmor | $SUDO tee /usr/share/keyrings/redis.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/redis.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | $SUDO tee /etc/apt/sources.list.d/redis.list

curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | $SUDO bash

echo -e "${GREEN}[5] تثبيت PHP و MariaDB و Nginx...${NC}"
$SUDO apt update -y
$SUDO apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl,redis} mariadb-server nginx git redis-server

$SUDO systemctl enable --now redis-server

echo -e "${GREEN}[6] تثبيت Composer...${NC}"
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

echo -e "${GREEN}[7] إنشاء مجلد التثبيت...${NC}"
$SUDO mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

echo -e "${GREEN}[8] تنزيل ملفات CtrlPanel...${NC}"
git clone https://github.com/Ctrlpanel-gg/panel.git ./ >/dev/null 2>&1

echo -e "${GREEN}[9] إعداد قاعدة البيانات...${NC}"
$SUDO mysql -u root -e "CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';"
$SUDO mysql -u root -e "CREATE DATABASE $DB_NAME;"
$SUDO mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1';"
$SUDO mysql -u root -e "FLUSH PRIVILEGES;"

echo -e "${GREEN}[10] تثبيت Composer Packages...${NC}"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

php artisan storage:link

echo -e "${GREEN}[11] إعداد Nginx...${NC}"

cat <<EOF | $SUDO tee /etc/nginx/sites-available/ctrlpanel.conf
server {
    listen 80;
    server_name $DOMAIN;
    root $INSTALL_DIR/public;
    index index.php;
    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

$SUDO ln -sf /etc/nginx/sites-available/ctrlpanel.conf /etc/nginx/sites-enabled/
$SUDO rm -f /etc/nginx/sites-enabled/default
$SUDO nginx -t && $SUDO systemctl restart nginx

$SUDO chown -R www-data:www-data $INSTALL_DIR/
$SUDO chmod -R 755 storage/* bootstrap/cache/

echo -e "${GREEN}[12] إعداد Cron & Queue Workers...${NC}"

(crontab -l 2>/dev/null; echo "* * * * * php $INSTALL_DIR/artisan schedule:run >> /dev/null 2>&1") | crontab -

cat <<EOF | $SUDO tee /etc/systemd/system/ctrlpanel.service
[Unit]
Description=Ctrlpanel Queue Worker

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php $INSTALL_DIR/artisan queue:work --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOF

$SUDO systemctl enable --now ctrlpanel.service

echo -e "${GREEN}[13] تثبيت SSL...${NC}"
$SUDO apt install -y certbot python3-certbot-nginx
$SUDO certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect

$SUDO systemctl restart nginx php8.3-fpm

echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN}✔ تم التثبيت بنجاح${NC}"
echo -e "🌍 https://$DOMAIN/installer"
echo -e "📦 DB USER: $DB_USER"
echo -e "🔑 DB PASS: $DB_PASSWORD"
echo -e "📁 DB NAME: $DB_NAME"
echo -e "${GREEN}====================================${NC}"