#!/bin/bash

# SSPanel 安装脚本 for Debian 12
# 域名: yuebin.uk

set -e

# 配置变量
DOMAIN="yuebin.uk"
DB_NAME="sspanel"
DB_USER="sspanel"
DB_PASSWORD=$(openssl rand -base64 16 | tr -d '/+' | cut -c1-16)
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16 | tr -d '/+' | cut -c1-16)
PANEL_VERSION="25.1.0"
APP_KEY=$(openssl rand -base64 32)
MU_KEY=$(openssl rand -base64 16)

# 日志记录
LOG_FILE="/var/log/sspanel_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "SSPanel 安装脚本"
echo "域名: $DOMAIN"
echo "安装日志: $LOG_FILE"
echo "=========================================="

# 错误检查函数
check_command() {
    if [ $? -ne 0 ]; then
        echo "错误: $1 执行失败"
        exit 1
    fi
}

# 检查系统版本和要求
check_system_requirements() {
    echo "检查系统要求..."
    
    # 检查是否为 Debian 12
    if ! grep -q "bookworm" /etc/os-release 2>/dev/null; then
        echo "警告: 此脚本主要为 Debian 12 (Bookworm) 设计，其他版本可能存在兼容性问题"
    fi
    
    # 检查是否为 root 用户
    if [ "$EUID" -ne 0 ]; then
        echo "错误: 请使用 root 权限运行此脚本"
        exit 1
    fi
    
    # 检查内存
    MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEMORY_MB=$((MEMORY_KB / 1024))
    if [ $MEMORY_MB -lt 1024 ]; then
        echo "警告: 当前内存 ${MEMORY_MB}MB，推荐至少 1GB 内存"
    fi
    
    # 检查磁盘空间
    DISK_AVAILABLE=$(df / | tail -1 | awk '{print $4}')
    DISK_AVAILABLE_GB=$((DISK_AVAILABLE / 1024 / 1024))
    if [ $DISK_AVAILABLE_GB -lt 10 ]; then
        echo "警告: 根分区可用空间不足 10GB，可能影响安装"
    fi
    
    echo "系统检查完成"
}

# 检查系统要求
check_system_requirements

# 更新系统
echo "更新系统包..."
apt update && apt upgrade -y
check_command "系统更新"

# 添加 PHP 8.4 官方仓库（按官方推荐）
echo "添加 PHP 8.4 仓库..."
curl -sSLo /tmp/php.gpg https://packages.sury.org/php/apt.gpg
gpg --dearmor < /tmp/php.gpg > /usr/share/keyrings/php-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/php-archive-keyring.gpg] \
  https://packages.sury.org/php/ bookworm main" > /etc/apt/sources.list.d/php.list

apt update
check_command "PHP 仓库添加"

# 安装必要软件
echo "安装必要软件..."
# 使用 Debian 默认 Nginx + PHP 8.4 组合，简单稳定
apt install -y nginx mariadb-server redis-server ufw certbot python3-certbot-nginx \
  php8.4-{bcmath,bz2,cli,common,curl,fpm,gd,gmp,igbinary,intl,mbstring,mysql,opcache,readline,redis,soap,xml,yaml,zip}
check_command "软件安装"

# 配置MySQL
echo "配置MySQL..."
systemctl start mysql
systemctl enable mysql

# 安全设置MySQL
mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
check_command "MySQL安全配置"

# 创建SSPanel数据库
mysql -u root -p$MYSQL_ROOT_PASSWORD <<EOF
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
check_command "数据库创建"

# 安装Composer
echo "安装Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
check_command "Composer安装"

# 创建网站目录
echo "创建网站目录..."
mkdir -p /www/wwwroot/$DOMAIN
cd /www/wwwroot/$DOMAIN

# 下载SSPanel
echo "下载SSPanel..."
wget https://github.com/Anankke/SSPanel-UIM/archive/refs/tags/$PANEL_VERSION.zip -O sspanel.zip
check_command "SSPanel下载"

unzip sspanel.zip
mv SSPanel-UIM-$PANEL_VERSION/* .
mv SSPanel-UIM-$PANEL_VERSION/.* . 2>/dev/null || true
rm -rf SSPanel-UIM-$PANEL_VERSION sspanel.zip

echo "SSPanel 下载解压完成"

# 安装PHP依赖
echo "安装PHP依赖..."
composer install --no-dev --optimize-autoloader --ignore-platform-reqs
check_command "Composer依赖安装"

# 配置 Nginx 用户
echo "配置 Nginx..."
sed -i 's/^user.*/user www-data;/' /etc/nginx/nginx.conf
systemctl start nginx && systemctl enable nginx
check_command "Nginx 配置"

# 配置防火墙（在SSL证书获取之前）
echo "配置防火墙..."
# 安装 UFW（如果未安装）
if ! command -v ufw &> /dev/null; then
    apt install -y ufw
    check_command "UFW 安装"
fi

# 配置防火墙规则
ufw allow 22/tcp    # SSH 端口，防止被锁定
ufw allow 80/tcp    # HTTP 端口（Let's Encrypt 域名验证需要）
ufw allow 443/tcp   # HTTPS 端口

# 启用防火墙
ufw --force enable
check_command "防火墙配置"

echo "防火墙配置完成 - 已开放端口: 22(SSH), 80(HTTP), 443(HTTPS)"

# 配置PHP（使用 PHP 8.4）
echo "配置PHP..."
sed -i 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.4/fpm/php.ini
sed -i 's/^max_execution_time.*/max_execution_time = 300/' /etc/php/8.4/fpm/php.ini
sed -i 's/^memory_limit.*/memory_limit = 256M/' /etc/php/8.4/fpm/php.ini
sed -i 's/^post_max_size.*/post_max_size = 50M/' /etc/php/8.4/fpm/php.ini
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 50M/' /etc/php/8.4/fpm/php.ini
sed -i 's/^;date.timezone.*/date.timezone = Asia\/Shanghai/' /etc/php/8.4/fpm/php.ini

# 配置 PHP-FPM
sed -i 's/^;listen.owner.*/listen.owner = www-data/' /etc/php/8.4/fpm/pool.d/www.conf
sed -i 's/^;listen.group.*/listen.group = www-data/' /etc/php/8.4/fpm/pool.d/www.conf
sed -i 's/^;listen.mode.*/listen.mode = 0660/' /etc/php/8.4/fpm/pool.d/www.conf

systemctl restart php8.4-fpm && systemctl enable php8.4-fpm
check_command "PHP配置"

# 验证 PHP 扩展
echo "验证 PHP 扩展..."
REQUIRED_EXTENSIONS="bcmath curl fileinfo gmp json mbstring mysqli openssl pdo posix redis sodium xml yaml zip opcache"
MISSING_EXTENSIONS=""

for ext in $REQUIRED_EXTENSIONS; do
    if ! php8.4 -m | grep -qi "^$ext\$"; then
        MISSING_EXTENSIONS="$MISSING_EXTENSIONS $ext"
    fi
done

if [ -n "$MISSING_EXTENSIONS" ]; then
    echo "警告: 以下必需的 PHP 扩展未安装或未启用:$MISSING_EXTENSIONS"
    echo "请检查 PHP 配置"
else
    echo "所有必需的 PHP 扩展已正确安装"
fi

# 创建环境配置文件
cp config/.config.example.php config/.config.php
cp config/appprofile.example.php config/appprofile.php

# 配置环境文件
echo "配置环境文件..."
sed -i "s|'ChangeMe'|'$APP_KEY'|g" config/.config.php
sed -i "s|'ChangeMe'|'$MU_KEY'|g" config/.config.php
sed -i "s|https://example.com|https://$DOMAIN|g" config/.config.php
sed -i "s|db_database.*=.*'sspanel'|db_database = '$DB_NAME'|g" config/.config.php
sed -i "s|db_username.*=.*'root'|db_username = '$DB_USER'|g" config/.config.php
sed -i "s|db_password.*=.*'sspanel'|db_password = '$DB_PASSWORD'|g" config/.config.php
sed -i "s|redis_host.*=.*'127.0.0.1'|redis_host = 'localhost'|g" config/.config.php

# 设置文件权限
echo "设置文件权限..."
chown -R www-data:www-data /www/wwwroot/$DOMAIN
find /www/wwwroot/$DOMAIN -type d -exec chmod 755 {} \;
find /www/wwwroot/$DOMAIN -type f -exec chmod 644 {} \;

# 设置需要写权限的目录
chmod -R 777 /www/wwwroot/$DOMAIN/storage
chmod 775 /www/wwwroot/$DOMAIN/public/clients

# 确保 storage 子目录存在且可写
mkdir -p /www/wwwroot/$DOMAIN/storage/framework/smarty/{cache,compile}
mkdir -p /www/wwwroot/$DOMAIN/storage/framework/twig/cache
chmod -R 777 /www/wwwroot/$DOMAIN/storage/framework

# 配置文件权限
chmod 664 /www/wwwroot/$DOMAIN/config/.config.php
chmod 664 /www/wwwroot/$DOMAIN/config/appprofile.php

# 配置Nginx
echo "配置Nginx..."
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    root /www/wwwroot/$DOMAIN/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
    
    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Access-Control-Allow-Origin "*";
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 测试Nginx配置
nginx -t
check_command "Nginx配置测试"

systemctl reload nginx
check_command "Nginx重载"

# 获取SSL证书
echo "获取SSL证书..."
certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN || echo "SSL证书获取失败，请手动获取"

# 更新Nginx配置为HTTPS
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    root /www/wwwroot/$DOMAIN/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
    
    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Access-Control-Allow-Origin "*";
    }
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
}
EOF

# 重新加载Nginx
nginx -t
systemctl reload nginx

# 设置定时任务
echo "设置定时任务..."
(crontab -u www-data -l 2>/dev/null; echo "* * * * * php /www/wwwroot/$DOMAIN/xcat Job CheckJob") | crontab -u www-data -
(crontab -u www-data -l 2>/dev/null; echo "0 * * * * php /www/wwwroot/$DOMAIN/xcat Job UserJob") | crontab -u www-data -
(crontab -u www-data -l 2>/dev/null; echo "0 0 * * * php /www/wwwroot/$DOMAIN/xcat Job DailyJob") | crontab -u www-data -

echo "=========================================="
echo "SSPanel 安装完成！"
echo "=========================================="

# 输出版本信息
echo "=============== 版本信息 ==============="
echo "PHP 版本: $(php8.4 --version | head -n1)"
echo "Nginx 版本: $(nginx -v 2>&1 | cut -d' ' -f3)"
echo "MariaDB 版本: $(mysql --version | awk '{print $5}' | sed 's/,//')"
echo "Redis 版本: $(redis-server --version | awk '{print $3}' | cut -d'=' -f2)"
echo "SSPanel 版本: $PANEL_VERSION"
echo "防火墙状态: $(ufw status | head -1)"

# 输出重要信息
echo "================= 重要信息 ================="
echo "网站地址: https://$DOMAIN"
echo "MySQL root 密码: $MYSQL_ROOT_PASSWORD"
echo "SSPanel 数据库名: $DB_NAME"
echo "SSPanel 数据库用户: $DB_USER"
echo "SSPanel 数据库密码: $DB_PASSWORD"
echo "应用密钥: $APP_KEY"
echo "WebAPI 密钥: $MU_KEY"
echo "网站根目录: /www/wwwroot/$DOMAIN"
echo "=========================================="

echo ""
echo "后续步骤："
echo "1. 验证 PHP 扩展："
echo "   php8.4 -m | grep -E '(bcmath|curl|gmp|mbstring|mysqli|opcache|posix|redis|sodium|xml|yaml|zip)'"
echo "2. 检查防火墙状态："
echo "   ufw status"
echo "3. 运行数据库迁移："
echo "   cd /www/wwwroot/$DOMAIN && php xcat Migration latest"
echo "4. 创建管理员账户："
echo "   cd /www/wwwroot/$DOMAIN && php xcat User createAdmin"
echo "5. 导入默认设置："
echo "   cd /www/wwwroot/$DOMAIN && php xcat ImportSettings config/settings.sql"
echo "6. 访问: https://$DOMAIN"
echo ""
echo "如果SSL证书获取失败，请手动运行："
echo "   certbot --nginx -d $DOMAIN -d www.$DOMAIN"
echo "=========================================="

# 创建安装信息备份
cat > /www/wwwroot/$DOMAIN/install_info.txt <<EOF
安装时间: $(date)
域名: $DOMAIN
MySQL root 密码: $MYSQL_ROOT_PASSWORD
数据库名: $DB_NAME
数据库用户: $DB_USER
数据库密码: $DB_PASSWORD
应用密钥: $APP_KEY
WebAPI 密钥: $MU_KEY
EOF

chmod 600 /www/wwwroot/$DOMAIN/install_info.txt

echo "安装信息已保存到: /www/wwwroot/$DOMAIN/install_info.txt"
echo "请妥善保管这些信息！"
