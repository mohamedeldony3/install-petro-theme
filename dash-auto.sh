#!/bin/bash

# Auto CtrlPanel Installer (NO READ INPUTS)
# Values will be injected by the bot

DOMAIN="{{DOMAIN}}"
DB_PASSWORD="{{DB_PASSWORD}}"

DB_USER="ctrlpaneluser"
DB_NAME="ctrlpanel"
INSTALL_DIR="/var/www/ctrlpanel"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}بدء تثبيت CtrlPanel...${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}يجب تشغيل السكريبت بصلاحيات root${NC}"
    exit 1
fi

if [ ! -f /etc/debian_version ]; then
    echo -e "${RED}هذا السكربت مخصص لأنظمة ديبيان وأوبنتو${NC}"
    exit 1
fi

echo -e "${YELLOW}1) تحديث النظام...${NC}"
apt update -y && apt upgrade -y

echo -e "${YELLOW}2) تثبيت التبعيات...${NC}"
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release

echo -e "${YELLOW}3) إعداد مستودعات PHP و Redis و MariaDB...${NC}"
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list

curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" > /etc/apt/sources.list.d/redis.list

curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash

apt update -y

echo -e "${YELLOW}4) تثبيت PHP + MariaDB + Redis + NGINX...${NC}"
apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl,redis} mariadb-server nginx git redis-server

systemctl enable --now redis-server

echo -e "${YELLOW}5) تثبيت Composer...${NC}"
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

echo -e "${YELLOW}6) إنشاء مجلد التثبيت...${NC}"
mkdir -p $INSTALL_DIR && cd $INSTALL_DIR

echo -e "${YELLOW}7) تنزيل ملفات CtrlPanel...${NC}"
git clone https://github.com/Ctrlpanel-gg/panel.git ./

echo -e "${YELLOW}8) إعداد قاعدة البيانات...${NC}"
mysql -u root -e "CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';"
mysql -u root -e "CREATE DATABASE $DB_NAME;"
mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1';"
mysql -u root -e "FLUSH PRIVILEGES;"

echo -e "${YELLOW}9) تثبيت Composer dependencies...${NC}"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

php artisan storage:link

echo -e "${YELLOW}10) إعداد NGINX...${NC}"
cat > /etc/nginx/sites-available/ctrlpanel.conf << EOF
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
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

ln -sf /etc/nginx/sites-available/ctrlpanel.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl restart nginx

chown -R www-data:www-data $INSTALL_DIR/
chmod -R 755 storage/* bootstrap/cache/

(crontab -l 2>/dev/null; echo "* * * * * php $INSTALL_DIR/artisan schedule:run >> /dev/null 2>&1") | crontab -

echo -e "${YELLOW}11) تثبيت SSL...${NC}"
apt install -y certbot python3-certbot-nginx
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect

systemctl restart nginx php8.3-fpm

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}✔ تم التثبيت بنجاح!${NC}"
echo -e "${YELLOW}🔗 https://$DOMAIN/installer${NC}"
echo -e "${YELLOW}قاعدة البيانات:${NC}"
echo "DB User : $DB_USER"
echo "DB Pass : $DB_PASSWORD"
echo "DB Name : $DB_NAME"
echo -e "${GREEN}==========================================${NC}"