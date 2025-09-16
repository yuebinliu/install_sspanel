# install_sspanel

## 使用说明
此脚本适合debian12使用，运行前请先修改DOMAIN="yuebin.uk"为你自己的域名。

1. **保存脚本**：
```bash
wget https://raw.githubusercontent.com/yuebinliu/install_sspanel/refs/heads/main/install_sspanel.sh
#请先修改DOMAIN="yuebin.uk"
nano install_sspanel.sh
chmod +x install_sspanel.sh
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
