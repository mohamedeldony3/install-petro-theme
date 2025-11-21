#!/usr/bin/env bash
# Pterodactyl Panel One-Shot Installer (Ubuntu 22.04/24.04)
# Domain & Admin fixed (valid email required)

set -Eeuo pipefail

log()  { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err()  { echo -e "\033[1;31m[✗] $*\033[0m" >&2; }
die()  { err "$*"; exit 1; }

trap 'err "حدث خطأ غير متوقع. راجع السطور أعلاه — تمت معالجة أغلب الأخطاء الشائعة ليستمر التثبيت."' ERR

# ------------------------------
# إعدادات قابلة للتعديل
# ------------------------------
DOMAIN="boudy-host.arabdevs.xyz"
ADMIN_EMAIL="admin@boudy.xyz"   # <-- مهم: إيميل صالح فيه @
ADMIN_USERNAME="admin"
ADMIN_FIRST="admin"
ADMIN_LAST="admin"
ADMIN_PASSWORD="Admin1942003Mm"

APP_TIMEZONE="Africa/Cairo"
PANEL_DIR="/var/www/pterodactyl"
PHP_VERSION="8.3"
DB_NAME="panel"
DB_USER="pterodactyl"
DB_PASS="1942003"
ENABLE_UFW="${ENABLE_UFW:-0}"

[[ $EUID -eq 0 ]] || die "يرجى تشغيل السكربت كـ root"
export DEBIAN_FRONTEND=noninteractive

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

valid_email() {
  [[ "$1" =~ ^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$ ]]
}

domain_points_here() {
  local dig_ip=""; local pub_ip=""
  if have_cmd dig; then dig_ip="$(dig +short A "$DOMAIN" | tail -n1 || true)"; fi
  [[ -z "$dig_ip" ]] && dig_ip="$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}' || true)"
  pub_ip="$(curl -4fsS https://api.ipify.org || true)"
  [[ -n "$dig_ip" && -n "$pub_ip" && "$dig_ip" == "$pub_ip" ]]
}

port_listens_80() {
  ss -ltn | awk '{print $4}' | grep -qE '(:|^)80$' || nc -z -w2 127.0.0.1 80 >/dev/null 2>&1
}

setup_redis_repo() {
  local codename="$(lsb_release -cs || echo jammy)"
  local keyring="/usr/share/keyrings/redis-archive-keyring.gpg"
  local list="/etc/apt/sources.list.d/redis.list"
  log "تهيئة مستودع Redis الرسمي (محاولة آمنة)..."
  rm -f "$list" || true
  if curl -fsSL https://packages.redis.io/gpg | gpg --dearmor > "$keyring"; then
    echo "deb [signed-by=${keyring}] https://packages.redis.io/deb ${codename} main" > "$list"
    apt-get update -y && { log "تم إعداد مستودع Redis."; return 0; }
  fi
  warn "تعذّر إعداد مستودع Redis — سنستخدم حزمة أوبونتو."
  rm -f "$list" "$keyring" || true
  apt-get update -y || true
  return 1
}

# ------------------------------
# 0) فحوصات سريعة
# ------------------------------
valid_email "$ADMIN_EMAIL" || die "الإيميل غير صالح: ${ADMIN_EMAIL} — عدّله في أعلى السكربت (يجب أن يحتوي @)."

# ------------------------------
# 1) تحديث النظام
# ------------------------------
log "تحديث النظام..."
apt-get update -y
apt-get upgrade -y

timedatectl set-timezone "$APP_TIMEZONE" || warn "تعذّر ضبط المنطقة الزمنية؛ سنتابع."

apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release unzip git tar netcat-openbsd dnsutils

UBU_VER="$(lsb_release -rs || true)"

# ------------------------------
# 2) مستودع PHP (22.04 فقط)
# ------------------------------
if [[ "$UBU_VER" == "22.04" ]]; then
  log "إضافة مستودع PHP (ondrej/php) لـ 22.04..."
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
fi

# ------------------------------
# 3) Redis repo
# ------------------------------
setup_redis_repo || true

# ------------------------------
# 4) تثبيت الاعتمادات
# ------------------------------
log "تثبيت PHP ${PHP_VERSION} + Nginx + MariaDB + Redis..."
apt-get install -y \
  "php${PHP_VERSION}" "php${PHP_VERSION}-fpm" \
  "php${PHP_VERSION}-cli" "php${PHP_VERSION}-common" "php${PHP_VERSION}-gd" \
  "php${PHP_VERSION}-mysql" "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-bcmath" \
  "php${PHP_VERSION}-xml" "php${PHP_VERSION}-curl" "php${PHP_VERSION}-zip" \
  mariadb-server nginx redis-server

if ! have_cmd composer; then
  log "تثبيت Composer..."
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
fi

systemctl enable --now "php${PHP_VERSION}-fpm" nginx mariadb redis-server

# ------------------------------
# 5) تنزيل اللوحة
# ------------------------------
log "تنزيل Pterodactyl Panel..."
mkdir -p "${PANEL_DIR}"
cd "${PANEL_DIR}"
curl -fsSL -o panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# ------------------------------
# 6) قاعدة البيانات
# ------------------------------
log "تهيئة MariaDB..."
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

# ------------------------------
# 7) composer & APP_KEY (لا نعيد التوليد إن كان موجود)
# ------------------------------
log "composer install & key generate..."
cp -n .env.example .env
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction

if ! grep -q '^APP_KEY=base64:' .env || [[ -z "$(grep '^APP_KEY=' .env | cut -d= -f2)" ]]; then
  php artisan key:generate --force
else
  log "APP_KEY موجود — لن نعيد توليده."
fi

# ------------------------------
# 8) إعداد .env
# ------------------------------
log "تجهيز .env..."
HASHIDS_SALT="$(openssl rand -hex 20)"

sed -i "s|^APP_ENV=.*|APP_ENV=production|g" .env
sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|g" .env
sed -i "s|^APP_TIMEZONE=.*|APP_TIMEZONE=${APP_TIMEZONE}|g" .env
sed -i "s|^APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env
grep -q '^APP_ENVIRONMENT_ONLY=' .env && sed -i "s|^APP_ENVIRONMENT_ONLY=.*|APP_ENVIRONMENT_ONLY=false|g" .env || echo "APP_ENVIRONMENT_ONLY=false" >> .env

sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=mysql|g" .env
sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|g" .env
sed -i "s|^DB_PORT=.*|DB_PORT=3306|g" .env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|g" .env
sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|g" .env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" .env

sed -i "s|^REDIS_HOST=.*|REDIS_HOST=127.0.0.1|g" .env
sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=null|g" .env
sed -i "s|^REDIS_PORT=.*|REDIS_PORT=6379|g" .env

grep -q '^CACHE_DRIVER=' .env && sed -i "s|^CACHE_DRIVER=.*|CACHE_DRIVER=redis|g" .env || echo "CACHE_DRIVER=redis" >> .env
grep -q '^SESSION_DRIVER=' .env && sed -i "s|^SESSION_DRIVER=.*|SESSION_DRIVER=redis|g" .env || echo "SESSION_DRIVER=redis" >> .env
grep -q '^QUEUE_CONNECTION=' .env && sed -i "s|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|g" .env || echo "QUEUE_CONNECTION=redis" >> .env

grep -q '^MAIL_MAILER=' .env && sed -i "s|^MAIL_MAILER=.*|MAIL_MAILER=log|g" .env || echo "MAIL_MAILER=log" >> .env
grep -q '^MAIL_FROM_ADDRESS=' .env && sed -i "s|^MAIL_FROM_ADDRESS=.*|MAIL_FROM_ADDRESS=${ADMIN_EMAIL}|g" .env || echo "MAIL_FROM_ADDRESS=${ADMIN_EMAIL}" >> .env
grep -q '^MAIL_FROM_NAME=' .env && sed -i "s|^MAIL_FROM_NAME=.*|MAIL_FROM_NAME=\"${ADMIN_USERNAME}\"|g" .env || echo "MAIL_FROM_NAME=\"${ADMIN_USERNAME}\"" >> .env

grep -q '^HASHIDS_SALT=' .env && sed -i "s|^HASHIDS_SALT=.*|HASHIDS_SALT=${HASHIDS_SALT}|g" .env || echo "HASHIDS_SALT=${HASHIDS_SALT}" >> .env
grep -q '^HASHIDS_LENGTH=' .env || echo "HASHIDS_LENGTH=8" >> .env

# ------------------------------
# 9) migrate + seed
# ------------------------------
log "تشغيل migrations & seed..."
php artisan migrate --seed --force

# ------------------------------
# 10) إنشاء أدمن (مع Fallback آمن)
# ------------------------------
log "إنشاء مستخدم أدمن..."
set +e
php artisan p:user:make \
  --email="${ADMIN_EMAIL}" \
  --username="${ADMIN_USERNAME}" \
  --name-first="${ADMIN_FIRST}" \
  --name-last="${ADMIN_LAST}" \
  --password="${ADMIN_PASSWORD}" \
  --admin=1 \
  --no-interaction
CREATE_USER_RC=$?
set -e

if [[ $CREATE_USER_RC -ne 0 ]]; then
  warn "فشل p:user:make — تفعيل Fallback مباشر لقاعدة البيانات."
  set +e
  php artisan tinker --execute="echo \Pterodactyl\Models\User::where('email','${ADMIN_EMAIL}')->exists() ? 'OK' : 'MISS';" | grep -q OK
  USER_EXISTS_RC=$?
  set -e
  if [[ $USER_EXISTS_RC -ne 0 ]]; then
    php artisan tinker --execute="
      use Illuminate\Support\Str;
      use Illuminate\Support\Facades\Hash;
      use Illuminate\Support\Facades\DB;
      DB::table('users')->insert([
        'uuid'        => (string) Str::uuid(),
        'external_id' => null,
        'username'    => '${ADMIN_USERNAME}',
        'email'       => '${ADMIN_EMAIL}',
        'name_first'  => '${ADMIN_FIRST}',
        'name_last'   => '${ADMIN_LAST}',
        'password'    => Hash::make('${ADMIN_PASSWORD}'),
        'language'    => 'en',
        'root_admin'  => 1,
        'use_totp'    => 0,
        'created_at'  => now(),
        'updated_at'  => now(),
      ]);
      echo 'INSERTED';
    " | grep -q INSERTED || die "فشل إدراج المستخدم fallback."
    log "تم إنشاء الأدمن عبر fallback بنجاح."
  else
    log "الأدمن موجود مسبقًا — متابعة."
  fi
else
  log "تم إنشاء الأدمن بأمر artisan بنجاح."
fi

# ------------------------------
# 11) صلاحيات
# ------------------------------
log "ضبط صلاحيات الملفات..."
chown -R www-data:www-data "${PANEL_DIR}"
find "${PANEL_DIR}" -type d -exec chmod 755 {} \;
find "${PANEL_DIR}" -type f -exec chmod 644 {} \;

# ------------------------------
# 12) Nginx (HTTP) + فحص جاهزية الدومين
# ------------------------------
log "تكوين Nginx..."
rm -f /etc/nginx/sites-enabled/default || true
NGINX_CONF="/etc/nginx/sites-available/pterodactyl.conf"
cat > "${NGINX_CONF}" <<'NGINX'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;

    root /var/www/pterodactyl/public;
    index index.php index.html;
    charset utf-8;

    location / { try_files $uri $uri/ /index.php?$query_string; }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/log/nginx/pterodactyl.access.log;
    error_log  /var/log/nginx/pterodactyl.error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht { deny all; }
}
NGINX
sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" "${NGINX_CONF}"
ln -sf "${NGINX_CONF}" /etc/nginx/sites-enabled/pterodactyl.conf
nginx -t
systemctl restart nginx

# ------------------------------
# 13) SSL: تحقّق DNS + منفذ 80 ثم Certbot
# ------------------------------
log "التحقق من توجيه الدومين ومنفذ 80 قبل إصدار الشهادة..."
if domain_points_here && port_listens_80; then
  log "الدومين يشير لهذا السيرفر ومنفذ 80 يعمل — سنصدر شهادة."
  apt-get install -y certbot python3-certbot-nginx
  if certbot --nginx -d "${DOMAIN}" -m "${ADMIN_EMAIL}" --agree-tos --no-eff-email --redirect -n; then
    log "تم تفعيل HTTPS بنجاح."
  else
    warn "تعذّر إصدار الشهادة الآن (ACME/DNS/Rate-limit). سيعمل عبر HTTP مؤقتًا."
  fi
else
  warn "الدومين لا يشير للسيرفر أو منفذ 80 غير متاح — تخطّي إصدار الشهادة الآن."
fi

# ------------------------------
# 14) كرون كل دقيقة (بـ /etc/cron.d)
# ------------------------------
log "إضافة cron كل دقيقة..."
cat >/etc/cron.d/pterodactyl <<CRON
* * * * * root php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1
CRON
chmod 644 /etc/cron.d/pterodactyl
systemctl restart cron || true

# ------------------------------
# 15) خدمة الـ Queue
# ------------------------------
log "إنشاء خدمة systemd للـ queue worker..."
cat >/etc/systemd/system/pteroq.service <<'SERVICE'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now pteroq.service

# ------------------------------
# 16) UFW (اختياري)
# ------------------------------
if [[ "${ENABLE_UFW}" == "1" ]]; then
  log "تفعيل UFW وفتح SSH/HTTP/HTTPS..."
  apt-get install -y ufw
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
fi

# ------------------------------
# 17) ملخص
# ------------------------------
log "اكتمل التثبيت."
echo "  URL:        http://${DOMAIN}   (سيصبح https عند نجاح الشهادة)"
echo "  Email:      ${ADMIN_EMAIL}"
echo "  Username:   ${ADMIN_USERNAME}"
echo "  Password:   ${ADMIN_PASSWORD}"
