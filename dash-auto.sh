#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "[1] Updating system..."
apt update -y
apt upgrade -y

echo "[2] Installing dependencies..."
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release

echo "[3] Adding PHP repository (Ondrej)..."
LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/php -y

echo "[+] Updating..."
apt update -y

echo "[4] Installing PHP + Nginx + MariaDB..."
apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl,redis} \
 nginx mariadb-server git redis-server

echo "[5] Installing Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

echo "[6] Cloning CtrlPanel..."
mkdir -p /var/www/ctrlpanel
cd /var/www/ctrlpanel
git clone --depth=1 https://github.com/Ctrlpanel-gg/panel.git ./ || true

echo "[7] Database setup..."
DB_PASSWORD="{{DB_PASSWORD}}"
DB_USER="ctrlpaneluser"
DB_NAME="ctrlpanel"

mysql -u root <<EOF
DROP DATABASE IF EXISTS $DB_NAME;
CREATE DATABASE $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

echo "[8] Composer install..."
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

echo "[9] Linking storage..."
php artisan storage:link

echo "[10] Configuring Nginx..."
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

echo "[11] SSL setup..."
apt install -y certbot python3-certbot-nginx
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
 --email admin@$DOMAIN --redirect || true

echo "[12] Restarting services..."
systemctl restart nginx php8.3-fpm redis-server

echo "[✔] Installation completed successfully!"