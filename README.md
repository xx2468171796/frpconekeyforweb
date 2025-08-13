# FRPC 一键安装脚本 - 完整版

<div align="center">

![FRPC Logo](https://img.shields.io/badge/FRPC-v0.61.0-blue?style=for-the-badge&logo=github)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)
![Platform](https://img.shields.io/badge/Platform-Linux-orange?style=for-the-badge)
![Version](https://img.shields.io/badge/Version-v2.5.0-red?style=for-the-badge)

**🚀 一键安装 | 📱 可视化管理 | 🔧 完整功能**

</div>

## 📖 项目简介

这是一个功能完整的 FRPC（Fast Reverse Proxy Client）一键安装脚本，集成了现代化的 Web 管理面板。支持 Debian/Ubuntu/OpenWrt 系统，提供从安装到管理的完整解决方案。

### ✨ 核心特性

- 🎯 **一键安装**: 自动检测系统环境，智能安装配置
- 🌐 **Web 管理面板**: 现代化界面，支持可视化配置管理
- 🚇 **隧道管理**: 图形化添加、编辑、删除隧道配置
- 📊 **实时监控**: 系统状态、服务运行时间、资源使用情况
- 📥 **配置导入导出**: 支持 INI/TOML 格式互转，便于迁移
- 🔄 **自动重启**: 配置更改后自动重启服务
- 🛡️ **安全认证**: 内置用户认证系统
- 📱 **响应式设计**: 支持手机、平板、桌面设备

## 🎬 功能演示

### 主要界面
- **系统状态监控**: 实时显示 FRPC 服务状态、运行时间、系统资源
- **隧道管理**: 可视化添加 TCP/UDP/HTTP/HTTPS 隧道
- **配置编辑**: 内置代码编辑器，支持语法高亮和验证
- **日志查看**: 实时查看 FRPC 运行日志
- **服务控制**: 一键启动、停止、重启服务

### 支持的隧道类型
- **TCP 隧道**: SSH、数据库、游戏服务器等
- **UDP 隧道**: DNS、游戏、视频流等
- **HTTP 隧道**: Web 服务，支持自定义域名
- **HTTPS 隧道**: 安全 Web 服务，SSL 终端

## 🚀 快速开始

### 系统要求

- **操作系统**: Debian 8+, Ubuntu 16.04+, OpenWrt
- **架构支持**: amd64, arm64, armv7
- **权限要求**: root 用户或 sudo 权限
- **网络要求**: 能够访问 GitHub 和包管理源

### 一键安装

```bash
# 下载并运行安装脚本
wget -O frpc-install.sh https://raw.githubusercontent.com/your-repo/frpc-installer/main/frpc-installer-final-fixed-clean.sh
chmod +x frpc-install.sh
sudo ./frpc-install.sh
```

### 安装过程

1. **系统检测**: 自动识别操作系统和架构
2. **依赖安装**: 安装必要的系统依赖包
3. **FRPC 下载**: 从 GitHub 下载最新版本
4. **配置向导**: 引导配置服务器连接信息
5. **服务配置**: 自动创建系统服务
6. **Web 面板**: 启动管理界面

## 🎛️ 使用指南

### Web 管理面板

安装完成后，访问管理面板：

```
http://你的服务器IP:8080
```

**默认登录信息**:
- 用户名: `admin`
- 密码: 安装时设置的密码

### 基本配置

1. **服务器配置**
   - 服务器地址: 你的 FRPS 服务器地址
   - 服务器端口: 通常为 7000
   - 认证令牌: 与服务器端一致的 token

2. **添加隧道**
   - 隧道名称: 唯一标识符
   - 类型: TCP/UDP/HTTP/HTTPS
   - 本地地址: 127.0.0.1 或局域网设备 IP
   - 本地端口: 要映射的本地服务端口
   - 远程端口: 服务器端分配的端口

### 配置文件管理

- **导出配置**: 一键导出当前配置为 .txt 文件
- **导入配置**: 支持从其他 FRPC 客户端导入配置
- **格式转换**: 自动识别并转换 INI/TOML 格式
- **配置验证**: 实时验证配置文件语法

## 🔧 高级功能

### 命令行管理

```bash
# 查看服务状态
sudo systemctl status frpc

# 启动/停止/重启服务
sudo systemctl start frpc
sudo systemctl stop frpc
sudo systemctl restart frpc

# 查看实时日志
sudo journalctl -u frpc -f

# 编辑配置文件
sudo nano /etc/frpc/frpc.toml
```

### 配置文件示例

**TOML 格式** (推荐):
```toml
# 服务器配置
serverAddr = "your-server.com"
serverPort = 7000

# 认证配置
auth.method = "token"
auth.token = "your_secret_token"

# 日志配置
log.to = "/var/log/frpc.log"
log.level = "info"
log.maxDays = 3

# TCP 隧道示例
[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000

# HTTP 隧道示例
[[proxies]]
name = "web"
type = "http"
localIP = "127.0.0.1"
localPort = 80
customDomains = ["your-domain.com"]
```

## 🛠️ 故障排除

### 常见问题

**Q: 安装失败，提示依赖安装错误**
A: 运行脚本时选择"跳过依赖安装"，或手动安装依赖：
```bash
sudo apt-get update
sudo apt-get install wget curl python3 -y
```

**Q: Web 面板无法访问**
A: 检查防火墙设置和端口占用：
```bash
sudo ufw allow 8080
sudo netstat -tlnp | grep 8080
```

**Q: 隧道连接失败**
A: 检查配置和日志：
```bash
sudo journalctl -u frpc -n 50
```

**Q: 服务无法启动**
A: 检查配置文件语法：
```bash
sudo /usr/local/bin/frpc-bin verify -c /etc/frpc/frpc.toml
```

### 日志位置

- **系统日志**: `/var/log/frpc.log`
- **服务日志**: `journalctl -u frpc`
- **Web 面板日志**: 浏览器开发者工具

## 🔄 更新升级

### 自动更新

在 Web 面板中选择"更新 FRPC"，或运行：

```bash
sudo ./frpc-install.sh
# 选择菜单项 8: 更新 FRPC
```

### 手动更新

```bash
# 备份配置
sudo cp /etc/frpc/frpc.toml /etc/frpc/frpc.toml.backup

# 重新运行安装脚本
sudo ./frpc-install.sh
```

## 🌟 特色功能

### 智能系统适配
- **飞牛OS**: 特别优化的兼容模式
- **OpenWrt**: 轻量化安装选项
- **Docker**: 容器环境检测和适配

### 用户体验优化
- **中文界面**: 完全本土化的用户界面
- **操作提示**: 详细的操作说明和帮助信息
- **错误处理**: 友好的错误提示和解决建议
- **自动备份**: 配置更改前自动备份

### 安全特性
- **认证保护**: Web 面板登录认证
- **配置加密**: 敏感信息安全存储
- **访问控制**: 基于 IP 的访问限制
- **审计日志**: 完整的操作记录

## 📊 系统兼容性

| 操作系统 | 版本支持 | 架构支持 | 状态 |
|---------|---------|---------|------|
| Debian | 8+ | amd64, arm64, armv7 | ✅ 完全支持 |
| Ubuntu | 16.04+ | amd64, arm64, armv7 | ✅ 完全支持 |
| OpenWrt | 19.07+ | amd64, arm64, armv7 | ✅ 完全支持 |
| 飞牛OS | 全版本 | amd64, arm64 | ✅ 特别优化 |

## 🤝 社区支持

### 加入我们的社区

- 📱 **Telegram 群组**: [点击加入](https://t.me/+RZMe7fnvvUg1OWJl)
- 💬 **技术交流**: 分享使用经验，获取技术支持
- 🐛 **问题反馈**: 报告 Bug，提出改进建议
- 📚 **使用教程**: 获取最新教程和使用技巧

### 贡献指南

欢迎提交 Issue 和 Pull Request：

1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 📄 开源协议

本项目采用 MIT 协议开源 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

- [fatedier/frp](https://github.com/fatedier/frp) - 优秀的内网穿透工具
- 所有贡献者和用户的支持与反馈
- 开源社区的无私奉献

## 📞 联系方式

- **作者**: 孤独制作
- **Telegram**: [https://t.me/+RZMe7fnvvUg1OWJl](https://t.me/+RZMe7fnvvUg1OWJl)

---

<div align="center">

**⭐ 如果这个项目对你有帮助，请给个 Star 支持一下！**

**📱 加入 Telegram 群组获取更多支持: [https://t.me/+RZMe7fnvvUg1OWJl](https://t.me/+RZMe7fnvvUg1OWJl)**

</div>
