#!/usr/bin/env bash
set -Eeuo pipefail

log(){ echo -e "\033[1;32m[+] $*\033[0m"; }
err(){ echo -e "\033[1;31m[✗] $*\033[0m"; }
trap 'err "حدث خطأ غير متوقع"' ERR

# --------------------------
# VARIABLES FROM THE BOT
# --------------------------
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

# --------------------------
# STEP 1 – UPDATE SYSTEM
# --------------------------
echo "[STEP] UPDATE"
apt update -y
apt upgrade -y
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release unzip git tar dnsutils netcat-openbsd

# --------------------------
# STEP 2 – PHP Repository
# --------------------------
echo "[STEP] PHP_REPO"
UBU_VER="$(lsb_release -rs || true)"
if [[ "$UBU_VER" == "22.04" ]]; then
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
fi

# --------------------------
# STEP 3 – Redis Repo (Safe Mode)
# --------------------------
echo "[STEP] REDIS_REPO"
set +e
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis.gpg
REDIS_KEY=$?
if [[ $REDIS_KEY -eq 0 ]]; then
    echo "deb [signed-by=/usr/share/keyrings/redis.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/redis.list
    apt update -y
    echo "[OK] Redis repo added"
else
    echo "[WARN] Redis repo skipped — using Ubuntu Redis"
fi
set -e

# --------------------------
# STEP 4 – Install PHP + MariaDB + Nginx
# --------------------------
echo "[STEP] PHP_INSTALL"
apt install -y \
  php${PHP_VERSION} php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-common \
  php${PHP_VERSION}-gd php${PHP_VERSION}-mysql php${PHP_VERSION}-mbstring \
  php${PHP_VERSION}-bcmath php${PHP_VERSION}-xml php${PHP_VERSION}-zip \
  php${PHP_VERSION}-curl unzip git tar mariadb-server nginx redis-server

systemctl enable --now php${PHP_VERSION}-fpm mariadb nginx redis-server

# --------------------------
# STEP 5 – Download Panel
# --------------------------
echo "[STEP] DOWNLOAD_PANEL"
mkdir -p "${PANEL_DIR}"
cd "${PANEL_DIR}"
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz

# --------------------------
# STEP 6 – Fix Storage
# --------------------------
# --------------------------
# STEP 6 – Fix Storage
# --------------------------
echo "[STEP] FIX_STORAGE"

mkdir -p storage/{sessions,framework/{sessions,views,cache},logs}
mkdir -p bootstrap/cache

# الصلاحيات الصحيحة قبل key:generate
chown -R www-data:www-data storage bootstrap
chmod -R 775 storage bootstrap

# --------------------------
# STEP 7 – Copy .env
# --------------------------
echo "[STEP] ENV_COPY"
cp -n .env.example .env

# --------------------------
# STEP 8 – Generate Key AFTER fixing permission
# --------------------------
echo "[STEP] KEY_GENERATE"
sudo -u www-data php artisan key:generate --force
# --------------------------
# STEP 9 – Composer Install
# --------------------------
echo "[STEP] COMPOSER_INSTALL"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction

# --------------------------
# STEP 10 – Edit ENV
# --------------------------
echo "[STEP] ENV"
sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|g" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=${DB_USER}|g" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" .env
echo "APP_ENVIRONMENT_ONLY=false" >> .env

# --------------------------
# STEP 11 – Migrate + Seed
# --------------------------
echo "[STEP] ARTISAN"
php artisan migrate --seed --force

# --------------------------
# STEP 12 – Create Admin User
# --------------------------
echo "[STEP] ADMIN_USER"
php artisan p:user:make \
  --email="${ADMIN_EMAIL}" \
  --username="${ADMIN_USERNAME}" \
  --name-first="${ADMIN_FIRST}" \
  --name-last="${ADMIN_LAST}" \
  --password="${ADMIN_PASSWORD}" \
  --admin=1 \
  --no-interaction

# --------------------------
# STEP 13 – Permissions
# --------------------------
echo "[STEP] PERMISSIONS"
chown -R www-data:www-data "${PANEL_DIR}"
chmod -R 755 "${PANEL_DIR}"

# --------------------------
# STEP 14 – Nginx Setup
# --------------------------
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

# --------------------------
# STEP 15 – SSL
# --------------------------
echo "[STEP] SSL"
apt install -y certbot python3-certbot-nginx
certbot --nginx -d "${DOMAIN}" -m "${ADMIN_EMAIL}" --agree-tos --non-interactive || true

# --------------------------
# STEP 16 – DONE
# --------------------------
echo "[STEP] DONE"
echo "تم التثبيت بنجاح 🎉"
echo "الرابط: https://${DOMAIN}"
echo "البريد: ${ADMIN_EMAIL}"
echo "المستخدم: ${ADMIN_USERNAME}"