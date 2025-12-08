#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ============================
echo "[0] تنظيف اللوج والملفات..."
# ============================
rm -f /root/dash.log
touch /root/dash.log

log() {
    echo -e "$1" | tee -a /root/dash.log
}

DOMAIN="{{DOMAIN}}"
DB_PASSWORD="{{DB_PASSWORD}}"
INSTALL_DIR="/var/www/ctrlpanel"
DB_USER="ctrlpaneluser"
DB_NAME="ctrlpanel"

# ============================
log "[1] تحديث النظام..."
# ============================
apt update -y && apt upgrade -y

# ============================
log "[2] إزالة PHP 8.4 بالكامل لمنع التعارض..."
# ============================
apt remove -y "php8.4*" || true
apt autoremove -y || true

# ============================
log "[3] إزالة مستودعات PHP القديمة (Sury)..."
# ============================
rm -f /etc/apt/sources.list.d/php.list
rm -f /etc/apt/trusted.gpg.d/php.gpg
rm -f /etc/apt/sources.list.d/sury*
apt update -y || true

# ============================
log "[4] إضافة مستودع PHP الرسمي (Ondrej/php)..."
# ============================
apt install -y software-properties-common ca-certificates curl gnupg lsb-release
LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/php -y
apt update -y

# ============================
log "[5] تثبيت PHP 8.3 + Redis + Nginx + MariaDB..."
# ============================
apt install -y \
  php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl} \
  php8.3-redis \
  redis-server \
  nginx mariadb-server git

systemctl enable --now redis-server
systemctl restart php8.3-fpm

# ============================
log "[6] تثبيت Composer..."
# ============================
curl -sS https://getcomposer.org/installer \
 | php -- --install-dir=/usr/local/bin --filename=composer

# ============================
log "[7] تنزيل ملفات CtrlPanel..."
# ============================
rm -rf $INSTALL_DIR
mkdir -p $INSTALL_DIR
git clone https://github.com/Ctrlpanel-gg/panel.git $INSTALL_DIR

cd $INSTALL_DIR

# ============================
log "[8] إعداد قاعدة البيانات..."
# ============================

mysql -u root -e "DROP USER IF EXISTS '$DB_USER'@'localhost';"
mysql -u root -e "DROP USER IF EXISTS '$DB_USER'@'127.0.0.1';"
mysql -u root -e "DROP DATABASE IF EXISTS $DB_NAME;"

mysql -u root -e "CREATE DATABASE $DB_NAME;"
mysql -u root -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mysql -u root -e "CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';"
mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1';"
mysql -u root -e "FLUSH PRIVILEGES;"

log "[8.1] تعديل config/database.php لاستخدام MySQL الصحيح..."

sed -i "s/'database' => env('DB_DATABASE', .*/'database' => '$DB_NAME',/" config/database.php
sed -i "s/'username' => env('DB_USERNAME', .*/'username' => '$DB_USER',/" config/database.php
sed -i "s/'password' => env('DB_PASSWORD', .*/'password' => '$DB_PASSWORD',/" config/database.php

sed -i "/dashboard/d" config/database.php

php artisan config:clear || true
php artisan cache:clear || true
php artisan config:cache || true

# ============================
log "[9] تثبيت Composer Dependencies..."
# ============================
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

# ============================
log "[10] إعداد Laravel..."
# ============================
cp .env.example .env || true
php artisan key:generate || true

chown -R www-data:www-data /var/www/ctrlpanel
chmod -R 775 /var/www/ctrlpanel
chmod 664 /var/www/ctrlpanel/.env

php artisan storage:link

# ============================
log "[11] إعداد Nginx..."
# ============================
cat > /etc/nginx/sites-available/ctrlpanel.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $INSTALL_DIR/public;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

ln -sf /etc/nginx/sites-available/ctrlpanel.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl restart nginx

# ============================
log "[12] تثبيت SSL..."
# ============================
apt install -y certbot python3-certbot-nginx
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect || true

# ============================
log "[13] تشغيل الخدمات..."
# ============================
systemctl restart nginx php8.3-fpm redis-server mariadb

log "[✔] تم التثبيت بنجاح!"
log "🌍 الرابط: https://$DOMAIN/installer"
log "🔑 Database Password: $DB_PASSWORD"

rm -f dash.sh
exit 0