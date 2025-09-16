#!/bin/bash

# SSPanel 安装脚本 for Debian 12
# 域名: yuebin.uk

set -e

# 配置变量
DOMAIN="yuebin.uk"
DB_NAME="sspanel"
DB_USER="sspanel_user"
DB_PASSWORD=$(openssl rand -base64 16 | tr -d '/+' | cut -c1-16)
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16 | tr -d '/+' | cut -c1-16)
PANEL_VERSION="25.1.0"  # 最新稳定版本

echo "=========================================="
echo "SSPanel 安装脚本"
echo "域名: $DOMAIN"
echo "=========================================="

# 更新系统
echo "更新系统包..."
apt update && apt upgrade -y

# 安装必要软件
echo "安装必要软件..."
apt install -y curl wget git unzip nginx mariadb-server redis-server php8.2-fpm \
php8.2-common php8.2-mysql php8.2-gd php8.2-mbstring php8.2-xml php8.2-curl \
php8.2-bcmath php8.2-zip php8.2-intl php8.2-redis

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

# 创建SSPanel数据库
mysql -u root -p$MYSQL_ROOT_PASSWORD <<EOF
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# 安装Composer
echo "安装Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# 创建网站目录
echo "创建网站目录..."
mkdir -p /www/wwwroot/$DOMAIN
cd /www/wwwroot/$DOMAIN

# 下载SSPanel (使用无需认证的方式)
echo "下载SSPanel..."
# 方法1: 直接下载发布版压缩包
wget https://github.com/Anankke/SSPanel-UIM/archive/refs/tags/$PANEL_VERSION.zip -O sspanel.zip
unzip sspanel.zip
mv SSPanel-UIM-$PANEL_VERSION/* .
mv SSPanel-UIM-$PANEL_VERSION/.* . 2>/dev/null || true
rm -rf SSPanel-UIM-$PANEL_VERSION sspanel.zip

# 或者方法2: 使用无需认证的git下载（如果上面的方法失败）
# git clone https://github.com/Anankke/SSPanel-UIM.git . --depth=1
# git checkout $PANEL_VERSION

# 安装PHP依赖
echo "安装PHP依赖..."
composer install --no-dev --optimize-autoloader --ignore-platform-reqs

# 设置文件权限
chown -R www-data:www-data /www/wwwroot/$DOMAIN
chmod -R 755 /www/wwwroot/$DOMAIN
chmod -R 777 /www/wwwroot/$DOMAIN/storage
chmod -R 777 /www/wwwroot/$DOMAIN/public

# 配置Nginx
echo "配置Nginx..."
cat > /etc/nginx/sites-available/$DOMAIN <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /www/wwwroot/$DOMAIN/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 测试Nginx配置
nginx -t
systemctl reload nginx

# 配置PHP
echo "配置PHP..."
sed -i 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.2/fpm/php.ini
sed -i 's/^max_execution_time = .*/max_execution_time = 300/' /etc/php/8.2/fpm/php.ini
sed -i 's/^memory_limit = .*/memory_limit = 256M/' /etc/php/8.2/fpm/php.ini
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' /etc/php/8.2/fpm/php.ini
sed -i 's/^post_max_size = .*/post_max_size = 100M/' /etc/php/8.2/fpm/php.ini

systemctl restart php8.2-fpm

# 创建环境配置文件
cp .config.example.php .config.php
cp .env.example .env

# 生成密钥
APP_KEY=$(php -r "echo 'base64:' . base64_encode(random_bytes(32));")

# 配置环境文件
sed -i "s/#'app_key' => ''/'app_key' => '$APP_KEY'/" .config.php
sed -i "s/#'database_driver' => 'mysql'/'database_driver' => 'mysql'/" .config.php
sed -i "s/#'database_host' => 'localhost'/'database_host' => 'localhost'/" .config.php
sed -i "s/#'database_database' => ''/'database_database' => '$DB_NAME'/" .config.php
sed -i "s/#'database_username' => ''/'database_username' => '$DB_USER'/" .config.php
sed -i "s/#'database_password' => ''/'database_password' => '$DB_PASSWORD'/" .config.php
sed -i "s/#'database_charset' => 'utf8'/'database_charset' => 'utf8mb4'/" .config.php
sed -i "s/#'database_collation' => 'utf8_unicode_ci'/'database_collation' => 'utf8mb4_unicode_ci'/" .config.php

echo "=========================================="
echo "安装完成！请继续以下步骤："
echo "1. 访问 http://$DOMAIN 完成安装"
echo "2. 配置数据库连接"
echo "3. 运行数据库迁移"
echo "=========================================="

# 输出重要信息
echo "================= 重要信息 ================="
echo "MySQL root 密码: $MYSQL_ROOT_PASSWORD"
echo "SSPanel 数据库名: $DB_NAME"
echo "SSPanel 数据库用户: $DB_USER"
echo "SSPanel 数据库密码: $DB_PASSWORD"
echo "应用密钥: $APP_KEY"
echo "网站根目录: /www/wwwroot/$DOMAIN"
echo "=========================================="

# 显示后续步骤
echo ""
echo "后续步骤："
echo "1. 运行数据库迁移："
echo "   cd /www/wwwroot/$DOMAIN && php xcat Migration latest"
echo "2. 创建管理员账户："
echo "   cd /www/wwwroot/$DOMAIN && php xcat User createAdmin"
echo "3. 设置定时任务："
echo "   crontab -u www-data -e"
echo "   添加："
echo "   * * * * * php /www/wwwroot/$DOMAIN/xcat Job CheckJob"
echo "   0 * * * * php /www/wwwroot/$DOMAIN/xcat Job DailyJob"
