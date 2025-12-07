#!/usr/bin/env bash
set -Eeuo pipefail

# ===========================
#   LOG SYSTEM (GLOBAL)
# ===========================
LOG_FILE="/root/panel_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ===========================
#   ERROR HANDLER
# ===========================
on_error() {
    echo -e "\n\033[1;31m[✗] حدث خطأ أثناء التثبيت!\033[0m"
    echo -e "\033[1;31m[!] السطر الذي حدث عنده الخطأ: $1\033[0m"
    echo -e "\033[1;33m[!] آخر 40 سطر من اللوج:\033[0m"
    tail -n 40 "$LOG_FILE" || true
    exit 1
}

trap 'on_error $LINENO' ERR

# ===========================
#   VARIABLES
# ===========================
DOMAIN="{{DOMAIN}}"
ADMIN_EMAIL="{{EMAIL}}"
ADMIN_USERNAME="{{ADMIN_USER}}"
ADMIN_FIRST="Admin"
ADMIN_LAST="Admin"
ADMIN_PASSWORD="{{ADMIN_PASS}}"

APP_TIMEZONE="Africa/Cairo"
PANEL_DIR="/var/www/pterodactyl"
PHP_VERSION="8.3"
DB_NAME="panel"
DB_USER="pterodactyl"
DB_PASS="1942003"

# ===========================
#   STEP 1 — UPDATE SYSTEM
# ===========================
echo "[STEP] UPDATE"
apt update -y
apt upgrade -y
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release unzip git tar dnsutils netcat-openbsd

# ===========================
#   STEP 2 — PHP REPO
# ===========================
echo "[STEP] PHP_REPO"
UBU_VER="$(lsb_release -rs || true)"
if [[ "$UBU_VER" == "22.04" ]]; then
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
fi

# ===========================
#   STEP 3 — REDIS REPO
# ===========================
echo "[STEP] REDIS_REPO"
set +e
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis.gpg
if [[ $? -eq 0 ]]; then
    echo "deb [signed-by=/usr/share/keyrings/redis.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" > /etc/apt/sources.list.d/redis.list
    apt update -y
else
    echo "[WARN] Redis repo failed — using default redis"
fi
set -e

# ===========================
#   STEP 4 — INSTALL SERVICES
# ===========================
echo "[STEP] PHP_INSTALL"
apt install -y \
  php${PHP_VERSION} php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-common \
  php${PHP_VERSION}-gd php${PHP_VERSION}-mysql php${PHP_VERSION}-mbstring \
  php${PHP_VERSION}-bcmath php${PHP_VERSION}-xml php${PHP_VERSION}-zip \
  php${PHP_VERSION}-curl unzip git tar mariadb-server nginx redis-server composer

systemctl enable --now php${PHP_VERSION}-fpm mariadb nginx redis-server

# ===========================
#   STEP 5 — FIX STORAGE
# ===========================
echo "[STEP] FIX_STORAGE"
mkdir -p "${PANEL_DIR}"
cd "${PANEL_DIR}"
mkdir -p storage bootstrap/cache
chmod -R 755 storage bootstrap/cache

# ===========================
#   STEP 6 — DOWNLOAD PANEL
# ===========================
echo "[STEP] DOWNLOAD_PANEL"
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# ===========================
#   STEP 7 — DATABASE
# ===========================
echo "[STEP] DATABASE"
mariadb <<SQL
DROP USER IF EXISTS '${DB_USER}'@'localhost';
DROP USER IF EXISTS '${DB_USER}'@'127.0.0.1';
DROP USER IF EXISTS '${DB_USER}'@'%';

CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
CREATE USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';

GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';

FLUSH PRIVILEGES;
SQL

# ===========================
#   STEP 8 — ENV COPY
# ===========================
echo "[STEP] ENV_COPY"
cp -n .env.example .env

# ===========================
#   STEP 9 — COMPOSER INSTALL
# ===========================
echo "[STEP] COMPOSER_INSTALL"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction

# ===========================
#   STEP 10 — KEY GENERATE
# ===========================
echo "[STEP] KEY_GENERATE"
php artisan key:generate --force

# ===========================
#   STEP 11 — ENV UPDATE
# ===========================
echo "[STEP] ENV_UPDATE"
sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env
sed -i "s|APP_TIMEZONE=.*|APP_TIMEZONE=${APP_TIMEZONE}|g" .env

sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|g" .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|g" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|g" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" .env

echo "APP_ENVIRONMENT_ONLY=false" >> .env

# ===========================
#   STEP 12 — MIGRATE
# ===========================
echo "[STEP] MIGRATE"
php artisan migrate --seed --force

# ===========================
#   STEP 13 — ADMIN USER
# ===========================
echo "[STEP] ADMIN_USER"
php artisan p:user:make \
  --email="${ADMIN_EMAIL}" \
  --username="${ADMIN_USERNAME}" \
  --name-first="${ADMIN_FIRST}" \
  --name-last="${ADMIN_LAST}" \
  --password="${ADMIN_PASSWORD}" \
  --admin=1 \
  --no-interaction

# ===========================
#   STEP 14 — PERMISSIONS
# ===========================
echo "[STEP] PERMISSIONS"
chown -R www-data:www-data "${PANEL_DIR}"
chmod -R 755 "${PANEL_DIR}"

# ===========================
#   STEP 15 — NGINX
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
#   STEP 16 — SSL
# ===========================
echo "[STEP] SSL"
apt install -y certbot python3-certbot-nginx
certbot --nginx -d "${DOMAIN}" -m "${ADMIN_EMAIL}" --agree-tos --non-interactive || true

# ===========================
#   FINISHED
# ===========================
echo "[STEP] DONE"
echo "🎉 تم التثبيت بنجاح!"