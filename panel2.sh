#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/root/panel_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ===========================
#   ERROR HANDLER
# ===========================
on_error() {
    echo -e "\n\033[1;31m[✗] حدث خطأ أثناء التثبيت!\033[0m"
    echo -e "\033[1;31m[!] السطر الذي حدث عنده الخطأ: $1\033[0m"
    echo -e "\033[1;33m[!] آخر 40 سطر:\033[0m"
    tail -n 40 "$LOG_FILE" || true
    exit 1
}
trap 'on_error $LINENO' ERR

# ===========================
# VARIABLES
# ===========================
DOMAIN="{{DOMAIN}}"
ADMIN_EMAIL="{{EMAIL}}"
ADMIN_USERNAME="{{ADMIN_USER}}"
ADMIN_PASSWORD="{{ADMIN_PASS}}"

APP_TIMEZONE="Africa/Cairo"
PANEL_DIR="/var/www/pterodactyl"
PHP_VERSION="8.3"
DB_NAME="panel"
DB_USER="pterodactyl"
DB_PASS="1942003"

# ===========================
# UPDATE SYSTEM
# ===========================
echo "[STEP] UPDATE"
apt update -y
apt upgrade -y
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release unzip git tar dnsutils netcat-openbsd

# ===========================
# PHP REPO (لا تحتاج GPG)
# ===========================
echo "[STEP] PHP_REPO"
add-apt-repository -y ppa:ondrej/php || true
apt update -y

# ===========================
# INSTALL SERVICES
# ===========================
echo "[STEP] PHP_INSTALL"

# تثبيت PHP 8.3 (لخدمة NGINX)
apt install -y \
  php8.3 php8.3-fpm php8.3-cli php8.3-common \
  php8.3-gd php8.3-mysql php8.3-mbstring \
  php8.3-bcmath php8.3-xml php8.3-zip \
  php8.3-curl unzip git tar mariadb-server nginx redis-server composer

# إضافة الامتدادات الناقصة لنسخة 8.4 (مطلوبة للـ Composer)
apt install -y \
  php8.4-mysql php8.4-xml php8.4-simplexml php8.4-bcmath php8.4-dom php8.4-mbstring php8.4-gd php8.4-curl

systemctl enable --now php8.3-fpm mariadb nginx redis-server

# ===========================
# CREATE PANEL DIR
# ===========================
echo "[STEP] FIX_STORAGE"
mkdir -p "${PANEL_DIR}"
cd "${PANEL_DIR}"
mkdir -p storage bootstrap/cache
chmod -R 755 storage bootstrap/cache

# ===========================
# DOWNLOAD PANEL
# ===========================
echo "[STEP] DOWNLOAD_PANEL"
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# ===========================
# DATABASE
# ===========================
echo "[STEP] DATABASE"
mariadb <<SQL
DROP USER IF EXISTS '${DB_USER}'@'%';
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL

# ===========================
# ENVIRONMENT
# ===========================
echo "[STEP] ENV_COPY"
cp -n .env.example .env

# ===========================
# COMPOSER INSTALL
# ===========================
echo "[STEP] COMPOSER_INSTALL"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction

echo "[STEP] KEY_GENERATE"
php artisan key:generate --force

# ===========================
# UPDATE ENV
# ===========================
echo "[STEP] ENV_UPDATE"
sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env
sed -i "s|APP_TIMEZONE=.*|APP_TIMEZONE=${APP_TIMEZONE}|g" .env

sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|g" .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|g" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|g" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" .env

# ===========================
# MIGRATE DB
# ===========================
echo "[STEP] MIGRATE"
php artisan migrate --seed --force

# ===========================
# ADMIN USER
# ===========================
echo "[STEP] ADMIN_USER"
php artisan p:user:make \
  --email="${ADMIN_EMAIL}" \
  --username="${ADMIN_USERNAME}" \
  --name-first="Admin" \
  --name-last="Admin" \
  --password="${ADMIN_PASSWORD}" \
  --admin=1 \
  --no-interaction

# ===========================
# PERMISSIONS
# ===========================
echo "[STEP] PERMISSIONS"
chown -R www-data:www-data "${PANEL_DIR}"
chmod -R 755 "${PANEL_DIR}"

# ===========================
# NGINX CONFIG
# ===========================
echo "[STEP] NGINX"
cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root /var/www/pterodactyl/public;
    index index.php;

    location / { try_files \$uri \$uri/ /index.php?\$query_string; }

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# ===========================
# SSL (اختياري)
# ===========================
echo "[STEP] SSL"
apt install -y certbot python3-certbot-nginx
certbot --nginx -d "${DOMAIN}" -m "${ADMIN_EMAIL}" --agree-tos --non-interactive || true

# ===========================
# FINISHED
# ===========================
echo "[STEP] DONE"
echo "🎉 تم التثبيت بنجاح!"