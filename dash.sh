#!/bin/bash

# ألوان للعرض
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "${GREEN}بدء تثبيت CtrlPanel${NC}\n"

# التحقق من أن السكريبت يعمل كـ root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}يجب تشغيل السكريبت بصلاحيات root${NC}"
    exit 1
fi

# التحقق من نظام التشغيل
if [ ! -f /etc/debian_version ]; then
    echo -e "${RED}هذا السكريبت مخصص لأنظمة ديبيان/أوبنتو فقط${NC}"
    exit 1
fi

# --- طلب المعلومات من المستخدم ---
read -p "أدخل اسم الدومين (مثال: panel.example.com): " DOMAIN
read -s -p "أدخل كلمة مرور قاعدة البيانات: " DB_PASSWORD
echo ""

# تعيين باقي المتغيرات الثابتة
DB_USER="ctrlpaneluser"
DB_NAME="ctrlpanel"
INSTALL_DIR="/var/www/ctrlpanel"

# تأكيد القيم المدخلة
echo -e "${YELLOW}تم إدخال القيم التالية:${NC}"
echo "الدومين: $DOMAIN"
echo "كلمة مرور قاعدة البيانات: ********"
echo ""

read -p "هل تريد المتابعة؟ (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${RED}تم إلغاء التثبيت.${NC}"
    exit 1
fi

# --- بدء عملية التثبيت ---

echo -e "${YELLOW}جارٍ تحديث النظام...${NC}"
apt update && apt upgrade -y

echo -e "${YELLOW}جارٍ تثبيت التبعيات...${NC}"
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release

echo -e "${YELLOW}إعداد المستودعات...${NC}"
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash

apt update -y

echo -e "${YELLOW}جارٍ تثبيت الحزم...${NC}"
apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl,redis} mariadb-server nginx git redis-server

systemctl enable --now redis-server

echo -e "${YELLOW}جارٍ تثبيت Composer...${NC}"
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

echo -e "${YELLOW}إنشاء مجلد التثبيت...${NC}"
mkdir -p $INSTALL_DIR && cd $INSTALL_DIR

echo -e "${YELLOW}تنزيل ملفات CtrlPanel...${NC}"
git clone https://github.com/Ctrlpanel-gg/panel.git ./

echo -e "${YELLOW}إعداد قاعدة البيانات...${NC}"
mysql -u root -e "CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';"
mysql -u root -e "CREATE DATABASE $DB_NAME;"
mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1';"
mysql -u root -e "FLUSH PRIVILEGES;"

echo -e "${YELLOW}تثبيت حزم Composer...${NC}"
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

php artisan storage:link

echo -e "${YELLOW}إنشاء تكوين Nginx...${NC}"
cat > /etc/nginx/sites-available/ctrlpanel.conf << EOF
server {
    listen 80;
    server_name $DOMAIN;
    root $INSTALL_DIR/public;
    index index.php;

    access_log /var/log/nginx/ctrlpanel.app-access.log;
    error_log  /var/log/nginx/ctrlpanel.app-error.log error;

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

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/ctrlpanel.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

chown -R www-data:www-data $INSTALL_DIR/
chmod -R 755 storage/* bootstrap/cache/

(crontab -l 2>/dev/null; echo "* * * * * php $INSTALL_DIR/artisan schedule:run >> /dev/null 2>&1") | crontab -

cat > /etc/systemd/system/ctrlpanel.service << EOF
[Unit]
Description=Ctrlpanel Queue Worker

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php $INSTALL_DIR/artisan queue:work --sleep=3 --tries=3
StartLimitBurst=0

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now ctrlpanel.service

echo -e "${YELLOW}تثبيت SSL...${NC}"
apt install -y certbot python3-certbot-nginx
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect

systemctl restart nginx php8.3-fpm

echo -e "${GREEN}✅ تم التثبيت بنجاح!${NC}"
echo -e "${GREEN}قم بزيارة: https://$DOMAIN/installer لإكمال الإعداد${NC}"
echo -e "${YELLOW}بيانات قاعدة البيانات:${NC}"
echo "اسم المستخدم: $DB_USER"
echo "كلمة المرور: $DB_PASSWORD"
echo "قاعدة البيانات: $DB_NAME"