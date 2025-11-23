#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[1] تحديث النظام..."
apt update -y
apt upgrade -y

echo "[2] تثبيت المتطلبات..."
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release

echo "[3] إعداد مستودعات PHP و Redis و MariaDB..."
wget -q -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg

curl -fsSL https://packages.redis.io/gpg \
 | gpg --dearmor --yes --batch --output /usr/share/keyrings/redis-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
 | tee /etc/apt/sources.list.d/redis.list >/dev/null

curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash

apt update -y

echo "[4] تثبيت PHP + Nginx + MariaDB..."
apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl,redis} nginx mariadb-server git redis-server

echo "[5] تثبيت Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

echo "[6] تنزيل CtrlPanel..."
mkdir -p /var/www/ctrlpanel
cd /var/www/ctrlpanel
git clone https://github.com/Ctrlpanel-gg/panel.git ./ || true

echo "[7] إعداد قاعدة البيانات..."
DB_PASSWORD="{{DB_PASSWORD}}"
DB_USER="ctrlpaneluser"
DB_NAME="ctrlpanel"

mysql -u root -e "DROP DATABASE IF EXISTS $DB_NAME;"
mysql -u root -e "CREATE DATABASE $DB_NAME;"
mysql -u root -e "CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';"
mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1';"
mysql -u root -e "FLUSH PRIVILEGES;"

echo "[8] تثبيت Composer Packages..."
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

echo "[9] تفعيل رابط التخزين..."
php artisan storage:link

echo "[10] إعداد Nginx..."
DOMAIN="{{DOMAIN}}"

cat > /etc/nginx/sites-available/ctrlpanel.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/ctrlpanel/public;
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

echo "[11] تثبيت SSL..."
apt install -y certbot python3-certbot-nginx
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect || true

echo "[12] تشغيل خدمات..."
systemctl restart nginx php8.3-fpm redis-server

echo "[✔] تم التثبيت بنجاح!"