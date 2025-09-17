#!/bin/bash

# SSPanel-UIM 自动安装脚本 (完美版)
# 支持 Debian 12 和 Ubuntu
# 更新日期：2023-11-15

# 设置颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# 设置面板版本
PANEL_VERSION="25.1.0"

# 日志函数
log() {
    echo -e "${BLUE}[INFO]${RESET} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${RESET} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "${RED}[ERROR]${RESET} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

# 检查是否以root用户运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本必须以root权限运行"
        exit 1
    fi
}

# 检查系统类型
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        OS_ID=$ID
    else
        error "无法检测操作系统类型"
        exit 1
    fi
    
    log "检测到操作系统: $OS $VER (ID: $OS_ID)"
}

# 安装必要的依赖
install_dependencies() {
    log "安装必要的依赖包..."
    
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        apt update
        apt upgrade -y
        apt install -y curl wget git unzip software-properties-common \
            apt-transport-https ca-certificates gnupg2 lsb-release
    elif [[ "$OS_ID" == "centos" ]] || [[ "$OS_ID" == "rocky" ]]; then
        yum update -y
        yum install -y curl wget git unzip epel-release yum-utils
    else
        error "不支持的操作系统: $OS"
        exit 1
    fi
}

# 安装MySQL (支持Debian 12)
install_mysql() {
    log "安装MySQL..."
    
    if command -v mysql &> /dev/null; then
        warning "MySQL 已经安装，跳过安装步骤"
        return
    fi
    
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        # 使用MySQL官方APT仓库 (支持Debian 12)
        log "添加MySQL官方APT仓库..."
        
        # 下载并安装MySQL APT仓库
        wget https://dev.mysql.com/get/mysql-apt-config_0.8.28-1_all.deb
        if [ $? -eq 0 ]; then
            dpkg -i mysql-apt-config_0.8.28-1_all.deb
            apt update
        else
            # 如果特定版本下载失败，使用通用方法
            log "使用通用方法安装MySQL..."
            wget https://dev.mysql.com/get/mysql-apt-config_latest.deb
            dpkg -i mysql-apt-config_latest.deb
            apt update
        fi
        
        # 安装MySQL Server
        apt install -y mysql-server mysql-client
        
        systemctl start mysql
        systemctl enable mysql
        
    elif [[ "$OS_ID" == "centos" ]] || [[ "$OS_ID" == "rocky" ]]; then
        # 添加MySQL社区源
        rpm -Uvh https://dev.mysql.com/get/mysql80-community-release-el7-6.noarch.rpm
        yum install -y mysql-community-server mysql-community-client
        systemctl start mysqld
        systemctl enable mysqld
        
        # 获取临时密码并修改
        MYSQL_TEMP_PASSWORD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
        if [ ! -z "$MYSQL_TEMP_PASSWORD" ]; then
            mysql --connect-expired-password -u root -p"$MYSQL_TEMP_PASSWORD" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_password';
FLUSH PRIVILEGES;
EOF
        else
            # 如果没有临时密码，尝试空密码登录
            mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_password';
FLUSH PRIVILEGES;
EOF
        fi
    fi
    
    # MySQL安全设置
    log "执行MySQL安全设置..."
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        mysql -u root -p"$mysql_root_password" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    fi
    
    success "MySQL安装完成"
}

# 安装Redis
install_redis() {
    log "安装Redis..."
    
    if command -v redis-server &> /dev/null; then
        warning "Redis 已经安装，跳过安装步骤"
        return
    fi
    
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        apt install -y redis-server
        systemctl enable redis-server
        systemctl start redis-server
    elif [[ "$OS_ID" == "centos" ]] || [[ "$OS_ID" == "rocky" ]]; then
        yum install -y redis
        systemctl enable redis
        systemctl start redis
    fi
    
    # 基本Redis安全设置
    log "配置Redis..."
    if [ -f "/etc/redis/redis.conf" ]; then
        sed -i 's/bind 127.0.0.1/bind 127.0.0.1 ::1/g' /etc/redis/redis.conf
        sed -i 's/protected-mode yes/protected-mode yes/g' /etc/redis/redis.conf
        echo "maxmemory 512mb" >> /etc/redis/redis.conf
        echo "maxmemory-policy allkeys-lru" >> /etc/redis/redis.conf
        systemctl restart redis
    fi
    
    success "Redis安装完成"
}

# 安装PHP
install_php() {
    log "安装PHP 8.2..."
    
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        # 添加PHP PPA (支持Debian 12)
        add-apt-repository -y ppa:ondrej/php
        apt update
        
        # 安装PHP 8.2及所需扩展
        PHP_PACKAGES="php8.2 php8.2-fpm php8.2-cli php8.2-curl php8.2-common php8.2-json php8.2-mbstring php8.2-mysql php8.2-xml php8.2-zip php8.2-gd php8.2-intl php8.2-bcmath php8.2-redis php8.2-openssl php8.2-sqlite3"
        
        # 检查imagick扩展是否可用
        if apt-cache show php8.2-imagick &> /dev/null; then
            PHP_PACKAGES="$PHP_PACKAGES php8.2-imagick"
        else
            warning "php8.2-imagick 扩展不可用，跳过安装"
        fi
        
        apt install -y $PHP_PACKAGES
        
        # 配置PHP
        if [ -f "/etc/php/8.2/fpm/php.ini" ]; then
            sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.2/fpm/php.ini
            sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.2/fpm/php.ini
            sed -i 's/upload_max_filesize = .*/upload_max_filesize = 100M/' /etc/php/8.2/fpm/php.ini
            sed -i 's/post_max_size = .*/post_max_size = 100M/' /etc/php/8.2/fpm/php.ini
            systemctl restart php8.2-fpm
        fi
        
    elif [[ "$OS_ID" == "centos" ]] || [[ "$OS_ID" == "rocky" ]]; then
        # 添加Remi仓库
        yum install -y epel-release
        yum install -y https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %rhel).rpm
        yum-config-manager --enable remi-php82
        yum install -y php82 php82-php-fpm php82-php-cli php82-php-curl php82-php-common php82-php-json php82-php-mbstring php82-php-mysqlnd php82-php-xml php82-php-zip php82-php-gd php82-php-intl php82-php-bcmath php82-php-redis php82-php-openssl php82-php-sqlite3 php82-php-imagick
        
        # 创建符号链接
        ln -sf /usr/bin/php82 /usr/bin/php
        ln -sf /usr/sbin/php-fpm82 /usr/sbin/php-fpm
        
        # 配置PHP
        if [ -f "/etc/opt/remi/php82/php.ini" ]; then
            sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/opt/remi/php82/php.ini
            sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/opt/remi/php82/php.ini
            systemctl enable php82-php-fpm
            systemctl start php82-php-fpm
        fi
    fi
    
    success "PHP安装完成"
}

# 安装Node.js和Yarn
install_nodejs_yarn() {
    log "安装Node.js和Yarn..."
    
    if command -v node &> /dev/null; then
        warning "Node.js 已经安装，跳过安装步骤"
    else
        # 安装Node.js (支持Debian 12)
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt install -y nodejs
    fi
    
    if command -v yarn &> /dev/null; then
        warning "Yarn 已经安装，跳过安装步骤"
    else
        # 安装Yarn
        npm install -g yarn
    fi
    
    success "Node.js和Yarn安装完成"
}

# 安装Composer
install_composer() {
    log "安装Composer..."
    
    if command -v composer &> /dev/null; then
        warning "Composer 已经安装，跳过安装步骤"
        return
    fi
    
    # 使用官方安装方法
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    php -r "unlink('composer-setup.php');"
    
    success "Composer安装完成"
}

# 安装Nginx
install_nginx() {
    log "安装Nginx..."
    
    if command -v nginx &> /dev/null; then
        warning "Nginx 已经安装，跳过安装步骤"
        return
    fi
    
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        apt install -y nginx
    elif [[ "$OS_ID" == "centos" ]] || [[ "$OS_ID" == "rocky" ]]; then
        yum install -y nginx
    fi
    
    systemctl enable nginx
    systemctl start nginx
    
    success "Nginx安装完成"
}

# 配置防火墙
configure_firewall() {
    log "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 22/tcp
        ufw --force enable
        ufw reload
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --reload
    else
        warning "未找到支持的防火墙工具，请手动配置防火墙规则"
    fi
    
    success "防火墙配置完成"
}

# 创建SSPanel数据库
create_database() {
    log "创建SSPanel数据库..."
    
    # 测试MySQL连接
    if ! mysql -u root -p"$mysql_root_password" -e "SELECT 1;" &> /dev/null; then
        error "无法连接到MySQL，请检查root密码是否正确"
        exit 1
    fi
    
    mysql -u root -p"$mysql_root_password" <<EOF
CREATE DATABASE IF NOT EXISTS $db_name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # 检查数据库是否创建成功
    if mysql -u root -p"$mysql_root_password" -e "USE $db_name;" 2>/dev/null; then
        success "数据库创建成功"
    else
        error "数据库创建失败"
        exit 1
    fi
}

# 下载SSPanel文件
download_sspanel() {
    log "下载SSPanel v${PANEL_VERSION}..."
    
    cd /var/www || exit
    if [ -d "sspanel" ]; then
        warning "SSPanel目录已存在，跳过下载"
        return
    fi
    
    # 方法1: 直接下载发布版压缩包
    wget https://github.com/Anankke/SSPanel-UIM/archive/refs/tags/${PANEL_VERSION}.zip -O sspanel.zip
    
    if [ $? -ne 0 ]; then
        error "下载SSPanel失败，尝试方法2: git clone"
        # 方法2: 使用git clone
        git clone https://github.com/Anankke/SSPanel-Uim.git sspanel
        cd sspanel
        git checkout tags/${PANEL_VERSION}
    else
        # 解压文件
        unzip sspanel.zip
        mv SSPanel-UIM-${PANEL_VERSION} sspanel
        rm sspanel.zip
        cd sspanel
    fi
    
    success "SSPanel下载完成"
}

# 安装PHP依赖
install_php_dependencies() {
    log "安装PHP依赖..."
    
    cd /var/www/sspanel || exit
    
    # 尝试安装依赖，忽略imagick扩展如果不可用
    composer install --no-dev --optimize-autoloader --ignore-platform-req=ext-imagick
    
    # 检查vendor目录是否存在
    if [ ! -f "vendor/autoload.php" ]; then
        error "vendor/autoload.php 不存在，Composer依赖安装失败"
        exit 1
    fi
    
    success "PHP依赖安装完成"
}

# 编译前端资源
build_frontend() {
    log "编译前端资源..."
    
    cd /var/www/sspanel || exit
    
    yarn install
    yarn run build:production
    
    success "前端资源编译完成"
}

# 配置.config.php文件
configure_config() {
    log "配置.config.php文件..."
    
    cd /var/www/sspanel || exit
    
    # 复制配置文件
    cp config/.config.example.php config/.config.php
    
    # 生成随机密钥
    RANDOM_KEY=$(openssl rand -hex 16)
    RANDOM_MUKEY=$(openssl rand -hex 16)
    
    # 使用实际配置替换示例值
    sed -i "s/'key' => 'ChangeMe'/'key' => '$RANDOM_KEY'/" config/.config.php
    sed -i "s|'baseUrl' => 'https://example.com'|'baseUrl' => 'https://$domain'|" config/.config.php
    sed -i "s/'muKey' => 'ChangeMe'/'muKey' => '$RANDOM_MUKEY'/" config/.config.php
    sed -i "s/'db_database' => 'sspanel'/'db_database' => '$db_name'/" config/.config.php
    sed -i "s/'db_username' => 'root'/'db_username' => '$db_user'/" config/.config.php
    sed -i "s/'db_password' => 'sspanel'/'db_password' => '$db_password'/" config/.config.php
    sed -i "s/'redis_host' => '127.0.0.1'/'redis_host' => '127.0.0.1'/" config/.config.php
    
    # 设置正确的文件权限
    chown -R www-data:www-data .
    find . -type d -exec chmod 755 {} \;
    find . -type f -exec chmod 644 {} \;
    chmod -R 755 storage/
    chmod 660 config/.config.php
    
    success ".config.php 配置完成"
}

# 初始化数据库
init_database() {
    log "初始化数据库..."
    
    cd /var/www/sspanel || exit
    
    # 首先确认 vendor 目录存在
    if [ ! -f vendor/autoload.php ]; then
        error "vendor/autoload.php 不存在，请先运行 composer install"
        composer install --no-dev --optimize-autoloader
    fi
    
    # 执行数据库迁移（初始化全新数据库）
    php xcat Migration new
    
    # 更新到最新数据库版本
    php xcat Migration latest
    
    # 导入配置项
    php xcat Tool importSetting
    
    # 创建管理员账户
    php xcat Tool createAdmin
    
    success "数据库初始化完成"
}

# 配置Nginx
configure_nginx() {
    log "配置Nginx..."
    
    # 创建Nginx配置
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        CONFIG_FILE="/etc/nginx/sites-available/sspanel.conf"
        SITES_ENABLED_DIR="/etc/nginx/sites-enabled"
    else
        CONFIG_FILE="/etc/nginx/conf.d/sspanel.conf"
        SITES_ENABLED_DIR=""
    fi
    
    # 获取PHP-FPM socket路径
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        PHP_SOCKET="/var/run/php/php8.2-fpm.sock"
    else
        PHP_SOCKET="/var/opt/remi/php82/run/php-fpm/php-fpm.sock"
    fi
    
    cat > $CONFIG_FILE <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    root /var/www/sspanel/public;
    index index.php index.html;
    
    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }
    
    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:$PHP_SOCKET;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
    
    location ~ /\.(?!well-known).* {
        deny all;
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    
    # 启用站点 (Ubuntu/Debian)
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        ln -sf $CONFIG_FILE $SITES_ENABLED_DIR/
    fi
    
    # 测试Nginx配置
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl reload nginx
        success "Nginx配置完成并重载"
    else
        error "Nginx配置测试失败，请检查配置"
        exit 1
    fi
}

# 安装SSL证书 (可选)
install_ssl() {
    log "安装SSL证书..."
    
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        if command -v certbot &> /dev/null; then
            apt install -y certbot python3-certbot-nginx
            certbot --nginx -d $domain --non-interactive --agree-tos --email $ssl_email --redirect
            systemctl reload nginx
            success "SSL证书安装完成"
        else
            warning "Certbot未安装，跳过SSL证书安装"
            warning "请手动安装SSL证书: apt install certbot python3-certbot-nginx && certbot --nginx -d $domain"
        fi
    else
        warning "CentOS/Rocky Linux 需要手动安装SSL证书"
    fi
}

# 配置PHP-FPM
configure_php_fpm() {
    log "配置PHP-FPM..."
    
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        FPM_POOL_FILE="/etc/php/8.2/fpm/pool.d/www.conf"
    else
        FPM_POOL_FILE="/etc/opt/remi/php82/php-fpm.d/www.conf"
    fi
    
    if [ -f "$FPM_POOL_FILE" ]; then
        # 优化PHP-FPM配置
        sed -i 's/^pm = .*/pm = dynamic/' $FPM_POOL_FILE
        sed -i 's/^pm.max_children = .*/pm.max_children = 50/' $FPM_POOL_FILE
        sed -i 's/^pm.start_servers = .*/pm.start_servers = 5/' $FPM_POOL_FILE
        sed -i 's/^pm.min_spare_servers = .*/pm.min_spare_servers = 5/' $FPM_POOL_FILE
        sed -i 's/^pm.max_spare_servers = .*/pm.max_spare_servers = 10/' $FPM_POOL_FILE
        
        systemctl restart php8.2-fpm
    fi
    
    success "PHP-FPM配置完成"
}

# 设置cron任务
setup_cron() {
    log "设置cron任务..."
    
    (crontab -l 2>/dev/null; echo "* * * * * php /var/www/sspanel/xcat Job CheckJob") | crontab -
    (crontab -l 2>/dev/null; echo "0 */1 * * * php /var/www/sspanel/xcat Job UserJob") | crontab -
    (crontab -l 2>/dev/null; echo "0 0 * * * php /var/www/sspanel/xcat Job DailyJob") | crontab -
    (crontab -l 2>/dev/null; echo "*/5 * * * * php /var/www/sspanel/xcat Job CheckIn") | crontab -
    (crontab -l 2>/dev/null; echo "0 */1 * * * php /var/www/sspanel/xcat Job SendDiaryMail") | crontab -
    
    success "cron任务设置完成"
}

# 获取用户输入
get_user_input() {
    echo "请输入MySQL root密码:"
    read -s mysql_root_password
    echo "请再次输入MySQL root密码:"
    read -s mysql_root_password_confirm
    
    if [ "$mysql_root_password" != "$mysql_root_password_confirm" ]; then
        error "两次输入的密码不匹配"
        exit 1
    fi
    
    echo "请输入SSPanel数据库名称:"
    read db_name
    echo "请输入SSPanel数据库用户名:"
    read db_user
    echo "请输入SSPanel数据库密码:"
    read -s db_password
    echo "请再次输入SSPanel数据库密码:"
    read -s db_password_confirm
    
    if [ "$db_password" != "$db_password_confirm" ]; then
        error "两次输入的密码不匹配"
        exit 1
    fi
    
    echo "请输入您的域名:"
    read domain
    
    echo "请输入SSL证书邮箱 (用于Certbot):"
    read ssl_email
}

# 显示安装摘要
show_summary() {
    echo ""
    success "SSPanel 安装完成!"
    echo "============================================================"
    echo "数据库名称: $db_name"
    echo "数据库用户: $db_user"
    echo "域名: $domain"
    echo "网站根目录: /var/www/sspanel"
    echo "面板版本: $PANEL_VERSION"
    echo "============================================================"
    echo "接下来您需要:"
    echo "1. 通过浏览器访问 https://$domain 完成安装"
    echo "2. 检查配置文件: /var/www/sspanel/config/.config.php"
    echo "3. 设置备份策略和监控"
    echo "============================================================"
}

# 主函数
main() {
    echo "SSPanel-UIM 自动安装脚本 v${PANEL_VERSION}"
    echo "============================================================"
    
    check_root
    check_os
    get_user_input
    install_dependencies
    install_mysql
    install_redis
    install_php
    install_nodejs_yarn
    install_composer
    install_nginx
    configure_firewall
    
    # 创建数据库
    create_database
    
    # 下载和设置SSPanel
    download_sspanel
    install_php_dependencies
    build_frontend
    configure_config
    
    # 初始化数据库
    init_database
    
    # 配置服务器
    configure_nginx
    configure_php_fpm
    install_ssl
    setup_cron
    
    show_summary
}

# 执行主函数
main "$@"
