
## 使用说明

1. **保存脚本**：
```bash
wget https://raw.githubusercontent.com/yuebinliu/install_sspanel/refs/heads/main/install_sspanel.sh
nano install_sspanel.sh
chmod +x install_sspanel.sh

wget https://github.com/yuebinliu/install_sspanel/raw/refs/heads/main/install_all.sh
chmod +x install_all.sh
./install_all.sh

wget https://github.com/yuebinliu/install_sspanel/raw/refs/heads/main/install_debian12.sh
chmod +x install_debian12.sh
./install_debian12.sh
```

2. **运行脚本**：
```bash
./install_sspanel.sh
```

3. **完成安装**：
- 访问 `http://yuebin.uk`
- 按照网页指引完成安装
- 运行数据库迁移命令：
```bash
cd /www/wwwroot/yuebin.uk
php xcat Migration latest
```

## 重要安全信息

脚本会自动生成以下凭据，请妥善保存：

- **MySQL root 密码**: 随机生成（脚本运行后显示）
- **SSPanel 数据库密码**: 随机生成（脚本运行后显示）
- **应用密钥**: 随机生成（用于加密会话）

## 后续步骤

1. **配置SSL证书**（推荐）：
```bash
apt install certbot python3-certbot-nginx
certbot --nginx -d yuebin.uk
```

2. **设置定时任务**：
```bash
crontab -u www-data -e
```
添加：
```
* * * * * php /www/wwwroot/yuebin.uk/xcat Job CheckJob
0 * * * * php /www/wwwroot/yuebin.uk/xcat Job DailyJob
```

3. **防火墙配置**：
```bash
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

这个脚本会自动处理大部分安装步骤，并在完成后显示所有重要的配置信息。请确保保存好生成的密码和密钥！

## install_debian12.sh
**主要改进内容**：

1. **完整的错误处理和日志记录**
    
2. **自动SSL证书配置**（使用Let's Encrypt）
    
3. **自动防火墙配置**（UFW，开放 22/80/443 端口）
    
4. **更安全的随机密钥生成**
    
5. **完整的Nginx安全配置**（包含安全头和缓存设置）
    
6. **安装信息备份文件**
    
7. **更好的权限管理**
    
8. **Redis配置集成**
    
9. **版本验证检查**

10. **PHP 8.4 完整扩展支持**（按 SSPanel 官方要求）
    

## 使用方法：

bash

# 给予执行权限
chmod +x install_sspanel.sh

# 运行脚本
./install_sspanel.sh

# 或者直接运行
bash install_sspanel.sh

这个脚本现在包含了完整的生产环境配置，包括SSL证书、安全头、错误处理等。安装完成后记得按照提示完成数据库迁移和管理员账户创建。
