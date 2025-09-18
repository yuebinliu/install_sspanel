# Nginx 配置目录问题解决方案

## 问题描述

在运行 `install_debian12.sh` 时出现错误：
```
./install_debian12.sh: line 231: /etc/nginx/sites-available/yuebin.uk: No such file or directory
```

## 问题原因

这个问题是由于 **Nginx 版本差异** 导致的配置目录结构不同：

### 1. Debian 默认版本 Nginx
- 配置目录：`/etc/nginx/sites-available/` 和 `/etc/nginx/sites-enabled/`
- 通过软链接方式启用站点配置
- 通过 `apt install nginx` 安装

### 2. Nginx 官方版本
- 配置目录：`/etc/nginx/conf.d/`
- 自动加载 `conf.d` 目录中的 `.conf` 文件
- 通过官方仓库安装（我们脚本中使用的版本）

## 解决方案

### 修改内容：

1. **动态检测 Nginx 版本类型**：
   ```bash
   if [ -d "/etc/nginx/sites-available" ]; then
       # Debian 默认版本配置
       NGINX_CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"
       NGINX_ENABLE_CMD="ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/"
       NGINX_DISABLE_DEFAULT="rm -f /etc/nginx/sites-enabled/default"
   else
       # Nginx 官方版本配置
       NGINX_CONFIG_FILE="/etc/nginx/conf.d/$DOMAIN.conf"
       NGINX_ENABLE_CMD="# 官方版本自动加载 conf.d 中的文件"
       NGINX_DISABLE_DEFAULT="mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak 2>/dev/null || true"
   fi
   ```

2. **使用变量存储配置文件路径**：
   ```bash
   cat > "$NGINX_CONFIG_FILE" <<EOF
   # 配置内容...
   EOF
   ```

3. **移除 snippets 依赖**：
   - 原配置：`include snippets/fastcgi-php.conf;`
   - 修改后：直接使用完整的 FastCGI 配置
   ```nginx
   location ~ \.php$ {
       fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
       fastcgi_index index.php;
       fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
       include fastcgi_params;
   }
   ```

## 修改优势

✅ **兼容性**：同时支持 Debian 默认版本和 Nginx 官方版本  
✅ **自动检测**：无需手动判断 Nginx 版本类型  
✅ **稳定性**：不依赖可能不存在的 snippets 文件  
✅ **标准化**：使用通用的 FastCGI 配置

## 验证方法

安装完成后，可以通过以下命令验证：

```bash
# 检查 Nginx 配置文件位置
ls -la /etc/nginx/sites-available/ 2>/dev/null || ls -la /etc/nginx/conf.d/

# 检查 Nginx 配置语法
nginx -t

# 检查 Nginx 服务状态
systemctl status nginx
```

## 后续建议

1. **测试环境**：建议在干净的 Debian 12 系统上测试
2. **日志监控**：安装过程中注意观察 Nginx 相关日志
3. **备份配置**：重要环境建议先备份原有配置

这个修改确保了脚本在不同的 Nginx 安装方式下都能正常工作。