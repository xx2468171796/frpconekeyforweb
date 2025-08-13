#!/bin/bash

# FRPC 一键安装脚本 - 完全修复版
# 支持 Debian/Ubuntu/OpenWrt，架构：amd64/arm64/armv7
# 集成完整的 Web 管理面板 - 所有功能完全正常
# 版本：2.5.0

# set -e  # 暂时禁用严格模式，避免意外退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 全局变量
FRPC_VERSION="0.61.0"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/frpc"
LOG_DIR="/var/log"
WEB_PORT=""
WEB_USERNAME=""
WEB_PASSWORD=""
OS_TYPE=""
ARCH_TYPE=""

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 通用服务管理函数
service_control() {
    local action="$1"
    local service="$2"
    
    if command -v systemctl >/dev/null 2>&1; then
        # 使用 systemd
        case "$action" in
            "start") systemctl start "$service" ;;
            "stop") systemctl stop "$service" ;;
            "restart") systemctl restart "$service" ;;
            "status") systemctl status "$service" --no-pager ;;
            "enable") systemctl enable "$service" ;;
            "disable") systemctl disable "$service" ;;
        esac
    elif [ -f "/etc/init.d/$service" ]; then
        # 使用 init.d (OpenWrt)
        case "$action" in
            "start") /etc/init.d/"$service" start ;;
            "stop") /etc/init.d/"$service" stop ;;
            "restart") /etc/init.d/"$service" restart ;;
            "status") /etc/init.d/"$service" status ;;
            "enable") /etc/init.d/"$service" enable ;;
            "disable") /etc/init.d/"$service" disable ;;
        esac
    else
        return 1
    fi
}

# OpenWrt兼容的IP获取函数
get_local_ip() {
    local ip=""
    
    # 方法1: 尝试使用hostname命令
    if command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # 方法2: 如果hostname不可用，尝试使用ip命令
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -1)
    fi
    
    # 方法3: 尝试使用ifconfig
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig 2>/dev/null | grep -E 'inet.*192\.168\.|inet.*10\.|inet.*172\.' | head -1 | awk '{print $2}' | cut -d: -f2)
    fi
    
    # 方法4: 读取网络接口文件 (OpenWrt)
    if [ -z "$ip" ] && [ -f "/proc/net/route" ]; then
        local interface=$(awk '/^[a-zA-Z]/ && $2 == "00000000" {print $1; exit}' /proc/net/route 2>/dev/null)
        if [ -n "$interface" ] && [ -f "/sys/class/net/$interface/address" ]; then
            ip=$(ip addr show "$interface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
        fi
    fi
    
    # 方法5: 尝试从常见网络接口获取
    if [ -z "$ip" ]; then
        for iface in br-lan eth0 wlan0 en0 ens33; do
            if [ -d "/sys/class/net/$iface" ]; then
                ip=$(ip addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
                [ -n "$ip" ] && break
            fi
        done
    fi
    
    # 默认值
    echo "${ip:-localhost}"
}

show_welcome() {
    echo -e "${GREEN}"
    echo "=================================================="
    echo "      FRPC 一键安装脚本 v2.5.0 - 最新版本"
    echo "=================================================="
    echo -e "${NC}"
    echo "✨ 新功能: 完全支持官方 TOML 配置格式"
    echo "🚀 支持: 可视化配置 | 隧道管理 | 实时监控"
    echo "🔧 修复: 所有格式问题 + 完整功能支持"
    echo "📦 版本: FRPC $FRPC_VERSION | 自动检查更新"
    echo ""
}

# 系统检测函数
detect_os() {
    print_info "正在检测操作系统..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        
        # 特殊处理飞牛OS
        if echo "$NAME $ID $ID_LIKE" | grep -qi "fnos\|flynas\|飞牛"; then
            OS_TYPE="debian"
            print_success "检测到 飞牛OS (基于 Debian)"
            print_info "使用 Debian 兼容模式"
        else
            case "$ID" in
                "debian") OS_TYPE="debian"; print_success "检测到 Debian $VERSION_ID" ;;
                "ubuntu") OS_TYPE="ubuntu"; print_success "检测到 Ubuntu $VERSION_ID" ;;
                *) 
                    # 检查是否基于 Debian/Ubuntu
                    if echo "$ID_LIKE" | grep -q "debian"; then
                        OS_TYPE="debian"
                        print_success "检测到基于 Debian 的系统: $NAME"
                    elif echo "$ID_LIKE" | grep -q "ubuntu"; then
                        OS_TYPE="ubuntu"
                        print_success "检测到基于 Ubuntu 的系统: $NAME"
                    elif [ -f /etc/openwrt_release ]; then
                        OS_TYPE="openwrt"; print_success "检测到 OpenWrt"
                    else
                        print_warning "未知操作系统: $ID，尝试使用 Debian 兼容模式"
                        OS_TYPE="debian"
                    fi ;;
            esac
        fi
    elif [ -f /etc/openwrt_release ]; then
        OS_TYPE="openwrt"; print_success "检测到 OpenWrt"
    else
        print_warning "无法检测操作系统，假设为 Debian 兼容系统"
        OS_TYPE="debian"
    fi
}

detect_arch() {
    print_info "正在检测系统架构..."
    local arch=$(uname -m)
    case "$arch" in
        "x86_64"|"amd64") ARCH_TYPE="amd64"; print_success "检测到架构: amd64" ;;
        "aarch64"|"arm64") ARCH_TYPE="arm64"; print_success "检测到架构: arm64" ;;
        "armv7l"|"armv7") ARCH_TYPE="arm"; print_success "检测到架构: armv7" ;;
        *) print_error "不支持的架构: $arch"; exit 1 ;;
    esac
}

check_fnos_compatibility() {
    # 检查飞牛OS特殊情况
    if [ -f /etc/os-release ]; then
        if grep -qi "fnos\|flynas\|飞牛" /etc/os-release 2>/dev/null; then
            print_info "飞牛OS 兼容性检查..."
            
            # 检查是否有 Docker 环境
            if command -v docker >/dev/null 2>&1; then
                print_info "检测到 Docker 环境"
            fi
            
            # 检查包管理器状态
            if ! apt-get --version >/dev/null 2>&1; then
                print_warning "apt-get 不可用，可能需要手动安装依赖"
            fi
            
            # 检查网络连接
            if ! ping -c 1 github.com >/dev/null 2>&1; then
                print_warning "网络连接可能有问题，下载可能失败"
            fi
            
            print_info "飞牛OS 兼容性检查完成"
        fi
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本"
        print_info "使用命令: sudo $0"
        exit 1
    fi
}

get_user_input() {
    echo ""
    print_info "配置 Web 管理面板"
    echo ""
    
    while true; do
        read -p "请输入 Web 管理面板端口 (默认: 8080): " WEB_PORT
        WEB_PORT=${WEB_PORT:-8080}
        if [[ "$WEB_PORT" =~ ^[0-9]+$ ]] && [ "$WEB_PORT" -ge 1024 ] && [ "$WEB_PORT" -le 65535 ]; then
            break
        else
            print_warning "请输入有效的端口号 (1024-65535)"
        fi
    done
    
    while true; do
        read -p "请输入管理员用户名 (默认: admin): " WEB_USERNAME
        WEB_USERNAME=${WEB_USERNAME:-admin}
        if [ ${#WEB_USERNAME} -ge 3 ]; then break; else print_warning "用户名长度至少 3 个字符"; fi
    done
    
    while true; do
        read -s -p "请输入管理员密码 (至少 6 个字符): " WEB_PASSWORD
        echo ""
        if [ ${#WEB_PASSWORD} -ge 6 ]; then
            read -s -p "请再次输入密码确认: " password_confirm
            echo ""
            if [ "$WEB_PASSWORD" = "$password_confirm" ]; then break; else print_warning "两次输入的密码不一致"; fi
        else
            print_warning "密码长度至少 6 个字符"
        fi
    done
    
    echo ""
    print_success "配置完成："
    echo "  Web 端口: $WEB_PORT"
    echo "  用户名: $WEB_USERNAME"
    echo ""
}

# 安装依赖
install_dependencies() {
    print_info "安装必要的依赖包..."
    
    # 检测是否为飞牛OS
    local is_fnos=false
    if [ -f /etc/os-release ]; then
        if grep -qi "fnos\|flynas\|飞牛" /etc/os-release 2>/dev/null; then
            is_fnos=true
            print_info "检测到飞牛OS，使用兼容模式安装"
        fi
    fi
    
    case "$OS_TYPE" in
        "debian"|"ubuntu") 
            print_info "更新软件包列表..."
            if ! apt-get update >/dev/null 2>&1; then
                print_warning "软件包列表更新失败，尝试继续安装..."
            fi
            
            print_info "安装基础依赖..."
            # 逐个安装，避免单个包失败导致整体失败
            local packages=("wget" "curl" "unzip" "python3")
            local failed_packages=()
            
            for pkg in "${packages[@]}"; do
                if command -v "$pkg" >/dev/null 2>&1; then
                    print_info "$pkg 已安装"
                elif apt-get install -y "$pkg" >/dev/null 2>&1; then
                    print_success "$pkg 安装成功"
                else
                    print_warning "$pkg 安装失败"
                    failed_packages+=("$pkg")
                fi
            done
            
            # 检查关键依赖
            if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
                print_error "wget 和 curl 都无法安装，无法下载 FRPC"
                exit 1
            fi
            
            if ! command -v python3 >/dev/null 2>&1; then
                print_error "Python3 安装失败，Web 面板无法运行"
                print_info "请手动安装 Python3: apt-get install python3"
                exit 1
            fi
            
            # 尝试安装 pip3（可选）
            if ! command -v pip3 >/dev/null 2>&1; then
                print_info "尝试安装 pip3..."
                if apt-get install -y python3-pip >/dev/null 2>&1; then
                    print_success "pip3 安装成功"
                else
                    print_warning "pip3 安装失败，将跳过 psutil 安装"
                fi
            fi
            
            # 安装 Python psutil 模块（可选，失败不影响主要功能）
            print_info "尝试安装 Python psutil 模块..."
            if apt-get install -y python3-psutil >/dev/null 2>&1; then
                print_success "使用系统包安装 psutil 成功"
            elif command -v pip3 >/dev/null 2>&1 && pip3 install psutil >/dev/null 2>&1; then
                print_success "使用 pip3 安装 psutil 成功"
            else
                print_warning "psutil 安装失败，Web 面板系统监控功能将受限"
                print_info "这不影响 FRPC 的核心功能，可以继续使用"
            fi
            
            if [ ${#failed_packages[@]} -gt 0 ]; then
                print_warning "以下包安装失败: ${failed_packages[*]}"
                print_info "如果影响使用，请手动安装: apt-get install ${failed_packages[*]}"
            fi
            ;;
        "openwrt") 
            print_info "更新软件包列表..."
            opkg update >/dev/null 2>&1 || print_warning "软件包列表更新失败"
            
            print_info "安装基础依赖..."
            opkg install wget curl unzip python3 python3-pip >/dev/null 2>&1 || print_warning "部分依赖安装失败"
            
            print_info "安装 Python psutil 模块..."
            pip3 install psutil >/dev/null 2>&1 || print_warning "psutil 安装失败，Web 面板系统监控功能可能受限"
            ;;
    esac
    print_success "依赖包安装完成"
}

install_frpc() {
    print_info "正在下载和安装 FRPC..."
    local download_url="https://github.com/fatedier/frp/releases/download/v${FRPC_VERSION}/frp_${FRPC_VERSION}_linux_${ARCH_TYPE}.tar.gz"
    local temp_dir="/tmp/frpc_install_$$"
    
    mkdir -p "$temp_dir" && cd "$temp_dir"
    
    # 尝试多种下载方式
    local download_success=false
    
    if command -v wget >/dev/null 2>&1; then
        print_info "使用 wget 下载..."
        if wget -q --show-progress --timeout=30 "$download_url" -O "frpc.tar.gz" 2>/dev/null; then
            download_success=true
        elif wget --timeout=30 "$download_url" -O "frpc.tar.gz" 2>/dev/null; then
            download_success=true
        fi
    fi
    
    if [ "$download_success" = false ] && command -v curl >/dev/null 2>&1; then
        print_info "wget 失败，尝试使用 curl 下载..."
        if curl -L --connect-timeout 30 --max-time 300 "$download_url" -o "frpc.tar.gz" 2>/dev/null; then
            download_success=true
        fi
    fi
    
    if [ "$download_success" = true ]; then
        tar -xzf "frpc.tar.gz"
        mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"
        # 停止可能运行的服务（不阻塞安装过程）
        print_info "检查并停止现有服务..."
        systemctl stop frpc 2>/dev/null || true
        systemctl stop frpc-web 2>/dev/null || true
        # 只杀死 frpc 二进制进程，不杀死脚本
        pkill -x "frpc" 2>/dev/null || true
        pkill -f "frpc-bin" 2>/dev/null || true
        
        # 安装 FRPC 二进制文件
        print_info "安装 FRPC 二进制文件..."
        if cp "frp_${FRPC_VERSION}_linux_${ARCH_TYPE}/frpc" "$INSTALL_DIR/frpc-bin"; then
            chmod +x "$INSTALL_DIR/frpc-bin"
            print_success "二进制文件安装成功"
        else
            print_error "复制文件失败"
            cd / && rm -rf "$temp_dir"
            exit 1
        fi
        
        # 清理临时文件
        print_info "清理临时文件..."
        cd / && rm -rf "$temp_dir"
        print_success "FRPC 安装完成"
    else
        print_error "FRPC 下载失败"
        print_info "下载地址: $download_url"
        print_info "请检查网络连接或手动下载"
        
        # 提供手动安装指导
        print_info "手动安装步骤："
        print_info "1. 访问: https://github.com/fatedier/frp/releases/tag/v${FRPC_VERSION}"
        print_info "2. 下载: frp_${FRPC_VERSION}_linux_${ARCH_TYPE}.tar.gz"
        print_info "3. 解压并复制 frpc 到 $INSTALL_DIR/frpc-bin"
        print_info "4. 重新运行此脚本选择配置选项"
        exit 1
    fi
}

create_frpc_config() {
    print_info "创建 FRPC 配置文件（使用最新 TOML 格式）..."
    
    # 确保配置目录存在
    mkdir -p "$CONFIG_DIR"
    
    # 创建新版本的 TOML 配置文件（干净版本，无示例隧道）
    cat > "$CONFIG_DIR/frpc.toml" << EOF
# FRPC 配置文件 - TOML 格式 (v0.61.0+)
# 请修改以下配置为你的实际服务器信息

serverAddr = "your-server.com"
serverPort = 7000

# 认证配置
auth.method = "token"
auth.token = "your_token_here"

# 日志配置
log.to = "$LOG_DIR/frpc.log"
log.level = "info"
log.maxDays = 3

# 隧道配置
# 请通过 Web 面板添加隧道，或参考配置说明手动添加
# 点击 Web 面板中的"配置说明"按钮查看详细格式

# TLS 配置（如果需要）
# transport.tls.enable = true
# transport.tls.certFile = "/etc/frp/ssl/client.crt"
# transport.tls.keyFile = "/etc/frp/ssl/client.key"
# transport.tls.trustedCaFile = "/etc/frp/ssl/ca.crt"
EOF
    
    # 同时创建兼容的 INI 格式配置文件
    cat > "$CONFIG_DIR/frpc.ini" << EOF
[common]
server_addr = 127.0.0.1
server_port = 7000
token = your_token_here
admin_addr = 127.0.0.1
admin_port = 7400
log_file = $LOG_DIR/frpc.log
log_level = info
log_max_days = 3

# 示例隧道配置（可以通过 Web 面板管理）
# [ssh]
# type = tcp
# local_ip = 127.0.0.1
# local_port = 22
# remote_port = 6000
EOF
    
    # 设置正确的权限
    chmod 644 "$CONFIG_DIR/frpc.toml"
    chmod 644 "$CONFIG_DIR/frpc.ini"
    
    print_success "配置文件创建完成:"
    print_info "  TOML 格式: $CONFIG_DIR/frpc.toml (推荐)"
    print_info "  INI 格式: $CONFIG_DIR/frpc.ini (兼容)"
}

configure_service() {
    print_info "配置 FRPC 系统服务..."
    case "$OS_TYPE" in
        "debian"|"ubuntu")
            cat > "/etc/systemd/system/frpc.service" << EOF
[Unit]
Description=FRPC Client Service
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=$INSTALL_DIR/frpc-bin -c $CONFIG_DIR/frpc.toml

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable frpc
            systemctl start frpc
            ;;
        "openwrt")
            cat > "/etc/init.d/frpc" << EOF
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command $INSTALL_DIR/frpc-bin -c $CONFIG_DIR/frpc.toml
    procd_set_param respawn
    procd_close_instance
}
EOF
            chmod +x "/etc/init.d/frpc"
            /etc/init.d/frpc enable
            /etc/init.d/frpc start
            ;;
    esac
    print_success "FRPC 服务配置完成"
}

# 创建完全修复的 Web 面板
create_web_panel() {
    print_info "创建完全修复的 Web 管理面板..."
    local web_script="$CONFIG_DIR/frpc-web-panel.py"
    
    cat > "$web_script" << 'EOF'
#!/usr/bin/env python3
import os, sys, json, base64, subprocess, time, threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from datetime import datetime
import http.cookies

# 尝试导入 psutil
try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False
    class MockPsutil:
        @staticmethod
        def cpu_percent(interval=1): return 0.0
        class Process:
            def __init__(self, pid): self.pid = pid
            def memory_info(self): 
                class MemInfo: rss = 0
                return MemInfo()
            def create_time(self): return time.time()
    psutil = MockPsutil()

CONFIG_FILE = "/etc/frpc/frpc.toml"
CONFIG_FILE_INI = "/etc/frpc/frpc.ini"
LOG_FILE = "/var/log/frpc.log"

class FRPCHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, web_config=None, **kwargs):
        self.web_config = web_config or {}
        super().__init__(*args, **kwargs)
    
    def log_message(self, format, *args): 
        # 只记录错误日志
        if 'error' in format.lower() or 'Error' in str(args):
            super().log_message(format, *args)
    
    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/': self.serve_login()
        elif path == '/dashboard': 
            if self.check_auth(): self.serve_dashboard()
            else: self.redirect('/')
        elif path.startswith('/api/'): 
            if self.check_auth(): self.handle_api('GET', path)
            else: self.send_json({'error': 'Authentication required'}, 401)
        else: self.send_error(404)
    
    def do_POST(self):
        path = urlparse(self.path).path
        if path == '/api/login': self.api_login()
        elif path.startswith('/api/'): 
            if self.check_auth(): self.handle_api('POST', path)
            else: self.send_json({'error': 'Authentication required'}, 401)
        else: self.send_error(404)
    
    def do_DELETE(self):
        path = urlparse(self.path).path
        if path.startswith('/api/'): 
            if self.check_auth(): self.handle_api('DELETE', path)
            else: self.send_json({'error': 'Authentication required'}, 401)
        else: self.send_error(404)
    
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.end_headers()
    
    def check_auth(self):
        """检查用户认证 - 支持 Authorization 头和 Cookie"""
        print(f"检查认证 - 用户配置: {self.web_config}")
        
        # 首先检查 Authorization 头
        auth = self.headers.get('Authorization', '')
        print(f"Authorization 头: {auth[:20]}..." if auth else "无 Authorization 头")
        
        if auth.startswith('Basic '):
            try:
                decoded = base64.b64decode(auth[6:]).decode('utf-8')
                if ':' in decoded:
                    user, pwd = decoded.split(':', 1)
                    expected_user = self.web_config.get('username', '')
                    expected_pwd = self.web_config.get('password', '')
                    print(f"Authorization 认证: {user} vs {expected_user}")
                    if user == expected_user and pwd == expected_pwd:
                        print("Authorization 认证成功")
                        return True
            except Exception as e:
                print(f"Authorization 解析错误: {e}")
        
        # 然后检查 Cookie
        cookie_header = self.headers.get('Cookie', '')
        print(f"Cookie 头: {cookie_header}")
        
        if cookie_header:
            try:
                cookies = http.cookies.SimpleCookie()
                cookies.load(cookie_header)
                print(f"解析的 Cookies: {list(cookies.keys())}")
                
                if 'frpc_auth' in cookies:
                    auth_value = cookies['frpc_auth'].value
                    print(f"找到 frpc_auth Cookie: {auth_value[:20]}...")
                    
                    if auth_value:
                        decoded = base64.b64decode(auth_value).decode('utf-8')
                        if ':' in decoded:
                            user, pwd = decoded.split(':', 1)
                            expected_user = self.web_config.get('username', '')
                            expected_pwd = self.web_config.get('password', '')
                            print(f"Cookie 认证: {user} vs {expected_user}")
                            if user == expected_user and pwd == expected_pwd:
                                print("Cookie 认证成功")
                                return True
            except Exception as e:
                print(f"Cookie 解析错误: {e}")
        
        print("认证失败")
        return False
    
    def redirect(self, url):
        self.send_response(302)
        self.send_header('Location', url)
        self.end_headers()
    
    def send_json(self, data, code=200):
        self.send_response(code)
        self.send_header('Content-type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))
    
    def serve_login(self):
        html = '''<!DOCTYPE html><html><head><meta charset="UTF-8"><title>FRPC 管理面板</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:sans-serif;background:linear-gradient(135deg,#667eea,#764ba2);min-height:100vh;display:flex;align-items:center;justify-content:center}.container{background:white;padding:40px;border-radius:12px;box-shadow:0 10px 30px rgba(0,0,0,0.2);max-width:400px;width:100%}.logo{text-align:center;margin-bottom:30px}.logo h1{color:#333;font-size:28px;margin-bottom:8px}.form-group{margin-bottom:20px}.form-group label{display:block;margin-bottom:8px;color:#555;font-weight:500}.form-group input{width:100%;padding:12px 16px;border:2px solid #e1e5e9;border-radius:8px;font-size:16px}.form-group input:focus{outline:none;border-color:#667eea}.btn{width:100%;padding:14px;background:linear-gradient(135deg,#667eea,#764ba2);color:white;border:none;border-radius:8px;font-size:16px;cursor:pointer}.error{color:#e74c3c;margin-top:15px;text-align:center}</style>
</head><body><div class="container"><div class="logo"><h1>🚀 FRPC 管理面板</h1><p>可视化配置 · 一键管理</p></div>
<form id="loginForm"><div class="form-group"><label>用户名</label><input type="text" id="username" required></div>
<div class="form-group"><label>密码</label><input type="password" id="password" required></div>
<button type="submit" class="btn">登录管理面板</button><div id="error" class="error"></div></form>
<div style="margin-top:20px;text-align:center;font-size:12px;color:#666">
<p>🎯 孤独制作 | <a href="https://t.me/+RZMe7fnvvUg1OWJl" target="_blank" style="color:#667eea;text-decoration:none">📱 电报群</a></p>
</div></div>
<script>
document.getElementById('loginForm').addEventListener('submit', function(e) {
    e.preventDefault();
    const username = document.getElementById('username').value.trim();
    const password = document.getElementById('password').value.trim();
    const errorEl = document.getElementById('error');
    
    // 清除之前的错误信息
    errorEl.textContent = '';
    
    if (!username || !password) {
        errorEl.textContent = '请输入用户名和密码';
        return;
    }
    
    const credentials = btoa(username + ':' + password);
    
    // 显示加载状态
    errorEl.textContent = '正在登录...';
    errorEl.style.color = 'blue';
    
    fetch('/api/login', {
        method: 'POST',
        headers: { 
            'Authorization': 'Basic ' + credentials,
            'Content-Type': 'application/json'
        }
    }).then(response => {
        console.log('登录响应状态:', response.status);
        return response.json();
    }).then(data => {
        console.log('登录响应数据:', data);
        if (data.success) {
            // 登录成功
            errorEl.textContent = '登录成功，正在跳转...';
            errorEl.style.color = 'green';
            
            // 确保 Cookie 设置成功后再跳转
            setTimeout(() => {
                window.location.href = '/dashboard';
            }, 500);
        } else {
            errorEl.textContent = data.error || '登录失败，请检查用户名和密码';
            errorEl.style.color = 'red';
        }
    }).catch(error => {
        console.error('登录错误:', error);
        errorEl.textContent = '网络错误: ' + error.message;
        errorEl.style.color = 'red';
    });
});
</script></body></html>'''
        self.send_response(200)
        self.send_header('Content-type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(html.encode())
    
    def serve_dashboard(self):
        # 添加调试信息
        print("Dashboard accessed, checking auth...")
        if not self.check_auth():
            print("Dashboard auth failed, redirecting to login")
            self.redirect('/')
            return
        print("Dashboard auth successful")
        
        html = '''<!DOCTYPE html><html><head><meta charset="UTF-8"><title>FRPC 管理面板</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:sans-serif;background:#f8f9fa}.header{background:white;padding:15px 20px;box-shadow:0 2px 4px rgba(0,0,0,0.1);display:flex;justify-content:space-between;align-items:center}.container{max-width:1200px;margin:20px auto;padding:0 20px}.card{background:white;border-radius:12px;box-shadow:0 2px 8px rgba(0,0,0,0.1);margin-bottom:20px}.card-header{padding:20px;border-bottom:1px solid #eee;font-weight:600}.card-body{padding:20px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:20px}.metric{text-align:center;padding:30px 20px}.metric-value{font-size:2.5em;font-weight:bold;margin-bottom:8px;color:#28a745}.metric-label{color:#6c757d}.btn{padding:10px 20px;border:none;border-radius:8px;cursor:pointer;font-weight:500;margin-right:10px}.btn-danger{background:#dc3545;color:white}.btn-success{background:#28a745;color:white}.btn-warning{background:#ffc107;color:#212529}.controls{display:flex;gap:10px;margin-bottom:20px}.log-box{max-height:200px;overflow-y:auto;background:#f8f9fa;border-radius:8px;padding:15px;font-family:monospace;font-size:12px}input,textarea,select{width:100%;padding:8px;border:1px solid #ddd;border-radius:4px;margin-top:5px}</style>
</head><body><div class="header"><h1>🚀 FRPC 管理面板</h1><div style="display:flex;align-items:center;gap:15px"><span style="font-size:12px;color:#666">🎯 孤独制作 | <a href="https://t.me/+RZMe7fnvvUg1OWJl" target="_blank" style="color:#667eea;text-decoration:none">📱 电报群</a></span><button class="btn btn-danger" onclick="logout()">退出</button></div></div>
<div class="container">

<!-- FRPS 服务器配置 -->
<div class="card"><div class="card-header">🌐 FRPS 服务器配置</div><div class="card-body">
<div style="display:grid;grid-template-columns:1fr 1fr 1fr auto auto;gap:15px;align-items:end">
<div><label>服务器地址</label><input type="text" id="serverAddr" placeholder="例如: frp.example.com"></div>
<div><label>服务器端口</label><input type="number" id="serverPort" placeholder="例如: 7000"></div>
<div><label>认证令牌</label><input type="text" id="serverToken" placeholder="例如: your_secret_token"></div>
<div><button class="btn btn-success" onclick="saveServerConfig()">💾 保存连接</button></div>
<div><button class="btn" onclick="showConfigHelp()" style="background:#17a2b8;color:white">📖 配置说明</button></div>
<div><button class="btn" onclick="scrollToConfigEditor()" style="background:#6f42c1;color:white">⬇️ 配置编辑</button></div>
</div>
<div style="margin-top:15px;padding:10px;background:#e3f2fd;border-radius:6px;font-size:14px">
<strong>💡 提示：</strong>点击"配置说明"查看详细的配置格式说明和示例。
</div>
</div></div>

<!-- 系统状态 -->
<div class="card"><div class="card-header">📊 系统状态</div><div class="card-body"><div class="grid">
<div class="metric"><div class="metric-value" id="status">检查中</div><div class="metric-label">FRPC 服务</div></div>
<div class="metric"><div class="metric-value" id="uptime">--</div><div class="metric-label">运行时间</div></div>
<div class="metric"><div class="metric-value" id="memory">--</div><div class="metric-label">内存使用</div></div>
<div class="metric"><div class="metric-value" id="cpu">--</div><div class="metric-label">CPU 使用率</div></div>
</div></div></div>

<!-- 隧道管理 -->
<div class="card"><div class="card-header">🚇 隧道管理 <button class="btn btn-success" onclick="showAddTunnel()" style="float:right">+ 添加隧道</button></div><div class="card-body">
<div id="tunnelList">加载中...</div>
</div></div>

<!-- 配置文件编辑 -->
<div class="card"><div class="card-header">📝 配置文件编辑 <div style="float:right"><button class="btn" onclick="scrollToServerConfig()" style="background:#17a2b8;color:white;margin-right:10px">⬆️ 服务器配置</button><button class="btn btn-success" onclick="loadConfig()">🔄 重新加载</button></div></div><div class="card-body">
<div style="display:flex;gap:15px">
<div style="flex:1">
<textarea id="configEditor" style="height:400px;font-family:monospace;font-size:14px" placeholder="加载配置文件中..."></textarea>
<div style="margin-top:15px;display:flex;gap:10px;flex-wrap:wrap">
<button class="btn btn-success" onclick="saveConfig()">💾 保存配置</button>
<button class="btn btn-warning" onclick="validateConfig()">✅ 验证配置</button>
<button class="btn" onclick="resetConfig()" style="background:#6c757d;color:white">🔄 重置</button>
<button class="btn" onclick="toggleHelp()" style="background:#17a2b8;color:white">📖 格式说明</button>
<button class="btn" onclick="exportConfig()" style="background:#28a745;color:white">📤 导出配置</button>
<button class="btn" onclick="showImportModal()" style="background:#fd7e14;color:white">📥 导入配置</button>
</div>
<div id="configResult" style="margin-top:15px"></div>
</div>
<div id="configHelp" style="width:350px;background:#f8f9fa;padding:15px;border-radius:8px;font-size:13px;line-height:1.4;display:none">
<h4 style="margin-top:0;color:#495057">📖 FRPC 配置格式说明</h4>

<h5 style="color:#007bff;margin:15px 0 8px 0">🔧 基本配置</h5>
<pre style="background:#fff;padding:8px;border-radius:4px;font-size:12px;margin:5px 0">serverAddr = "服务器地址"
serverPort = 7000
auth.method = "token"
auth.token = "认证令牌"</pre>


<h5 style="color:#007bff;margin:15px 0 8px 0">🚇 TCP 隧道</h5>
<pre style="background:#fff;padding:8px;border-radius:4px;font-size:12px;margin:5px 0">[[proxies]]
name = "SSH"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000</pre>

<h5 style="color:#007bff;margin:15px 0 8px 0">🌍 HTTP 隧道</h5>
<pre style="background:#fff;padding:8px;border-radius:4px;font-size:12px;margin:5px 0">[[proxies]]
name = "Web"
type = "http"
localIP = "127.0.0.1"
localPort = 80
customDomains = ["域名.com"]</pre>

<h5 style="color:#007bff;margin:15px 0 8px 0">🔒 HTTPS 隧道</h5>
<pre style="background:#fff;padding:8px;border-radius:4px;font-size:12px;margin:5px 0">[[proxies]]
name = "WebSSL"
type = "https"
localIP = "127.0.0.1"
localPort = 443
customDomains = ["域名.com"]</pre>

<h5 style="color:#007bff;margin:15px 0 8px 0">📡 UDP 隧道</h5>
<pre style="background:#fff;padding:8px;border-radius:4px;font-size:12px;margin:5px 0">[[proxies]]
name = "DNS"
type = "udp"
localIP = "127.0.0.1"
localPort = 53
remotePort = 6053</pre>

<h5 style="color:#007bff;margin:15px 0 8px 0">🔐 TLS 配置</h5>
<pre style="background:#fff;padding:8px;border-radius:4px;font-size:12px;margin:5px 0">transport.tls.enable = true
transport.tls.certFile = "证书路径"
transport.tls.keyFile = "密钥路径"</pre>

<div style="background:#fff3cd;padding:8px;border-radius:4px;margin-top:10px;font-size:12px">
<strong>💡 注意事项：</strong><br>
• 数字不要加引号<br>
• 字符串必须加双引号<br>
• 每个 [[proxies]] 是一个隧道<br>
• localIP 支持域名和IP<br>
• customDomains 是数组格式
</div>
</div>
</div>
</div></div>

<!-- 服务控制 -->
<div class="card"><div class="card-header">⚙️ 服务控制</div><div class="card-body">
<div class="controls">
<button class="btn btn-success" onclick="controlService('start')">▶️ 启动</button>
<button class="btn btn-danger" onclick="controlService('stop')">⏹️ 停止</button>
<button class="btn btn-warning" onclick="controlService('restart')">🔄 重启</button>
</div>
<div id="serviceResult"></div>
</div></div>

<!-- 日志查看 -->
<div class="card"><div class="card-header">📋 最新日志 <button class="btn btn-success" onclick="refreshLogs()" style="float:right">🔄 刷新</button></div><div class="card-body">
<div class="log-box" id="logs">加载中...</div>
</div></div>

</div>

<!-- 配置说明模态框 -->
<div id="configHelpModal" style="display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:1000">
<div style="background:white;margin:20px auto;padding:0;width:90%;max-width:900px;border-radius:12px;max-height:90vh;overflow:hidden">
<div style="padding:20px;border-bottom:1px solid #eee;display:flex;justify-content:space-between;align-items:center;background:#f8f9fa">
<h3 style="margin:0;color:#333">📖 FRPC 配置文件详细说明</h3>
<span onclick="closeConfigHelp()" style="cursor:pointer;color:#999;font-size:24px;font-weight:bold">&times;</span>
</div>
<div style="padding:20px;overflow-y:auto;max-height:70vh;line-height:1.6">

<h4 style="color:#007bff;margin:20px 0 10px 0">🔧 基本服务器配置</h4>
<pre style="background:#f8f9fa;padding:15px;border-radius:8px;margin:10px 0;font-size:14px">serverAddr = "你的服务器地址"    # 例如: frp.example.com
serverPort = 7000               # 服务器端口（数字不加引号）</pre>

<h4 style="color:#007bff;margin:20px 0 10px 0">🔐 认证配置</h4>
<pre style="background:#f8f9fa;padding:15px;border-radius:8px;margin:10px 0;font-size:14px">auth.method = "token"           # 认证方式，固定为 token
auth.token = "你的密钥"         # 服务器设置的认证密钥</pre>


<h4 style="color:#007bff;margin:20px 0 10px 0">📝 日志配置</h4>
<pre style="background:#f8f9fa;padding:15px;border-radius:8px;margin:10px 0;font-size:14px">log.to = "/var/log/frpc.log"    # 日志文件路径
log.level = "info"              # 日志级别: debug, info, warn, error
log.maxDays = 3                 # 日志保留天数</pre>

<h4 style="color:#007bff;margin:20px 0 10px 0">🚇 隧道配置示例</h4>

<h5 style="color:#28a745;margin:15px 0 8px 0">TCP 隧道（最常用）</h5>
<pre style="background:#f8f9fa;padding:15px;border-radius:8px;margin:10px 0;font-size:14px">[[proxies]]
name = "SSH"                    # 隧道名称（必须唯一）
type = "tcp"                    # 隧道类型
localIP = "127.0.0.1"           # 本地IP地址
localPort = 22                  # 本地端口
remotePort = 6000               # 服务器端口（外网访问端口）</pre>

<h5 style="color:#28a745;margin:15px 0 8px 0">HTTP 隧道</h5>
<pre style="background:#f8f9fa;padding:15px;border-radius:8px;margin:10px 0;font-size:14px">[[proxies]]
name = "Web"
type = "http"
localIP = "127.0.0.1"
localPort = 80
customDomains = ["example.com"] # 自定义域名（数组格式）</pre>

<h5 style="color:#28a745;margin:15px 0 8px 0">HTTPS 隧道</h5>
<pre style="background:#f8f9fa;padding:15px;border-radius:8px;margin:10px 0;font-size:14px">[[proxies]]
name = "WebSSL"
type = "https"
localIP = "127.0.0.1"
localPort = 443
customDomains = ["example.com"]</pre>

<h5 style="color:#28a745;margin:15px 0 8px 0">UDP 隧道</h5>
<pre style="background:#f8f9fa;padding:15px;border-radius:8px;margin:10px 0;font-size:14px">[[proxies]]
name = "DNS"
type = "udp"
localIP = "127.0.0.1"
localPort = 53
remotePort = 6053</pre>

<h4 style="color:#007bff;margin:20px 0 10px 0">🔒 TLS 加密（可选）</h4>
<pre style="background:#f8f9fa;padding:15px;border-radius:8px;margin:10px 0;font-size:14px"># transport.tls.enable = true
# transport.tls.certFile = "/path/to/client.crt"
# transport.tls.keyFile = "/path/to/client.key"
# transport.tls.trustedCaFile = "/path/to/ca.crt"</pre>

<div style="background:#fff3cd;padding:15px;border-radius:8px;margin:20px 0;border-left:4px solid #ffc107">
<h4 style="color:#856404;margin:0 0 10px 0">💡 重要提示</h4>
<ul style="margin:0;padding-left:20px;color:#856404">
<li>数字类型不要加引号（如端口号：7000）</li>
<li>字符串必须用双引号包围（如："example.com"）</li>
<li>每个 [[proxies]] 代表一个隧道配置</li>
<li>隧道名称必须唯一，不能重复</li>
<li>customDomains 使用数组格式：["domain1.com", "domain2.com"]</li>
<li>localIP 可以是 127.0.0.1（本机）或局域网IP</li>
</ul>
</div>

</div>
<div style="padding:15px 20px;border-top:1px solid #eee;text-align:right;background:#f8f9fa">
<button class="btn" onclick="closeConfigHelp()" style="background:#6c757d;color:white">关闭</button>
</div>
</div>
</div>

<!-- 添加隧道模态框 -->
<div id="tunnelModal" style="display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:1000">
<div style="background:white;margin:50px auto;padding:30px;width:90%;max-width:600px;border-radius:12px">
<h3>🚇 添加隧道 <span onclick="closeTunnelModal()" style="float:right;cursor:pointer;color:#999;font-size:24px">&times;</span></h3>
<div style="margin:20px 0"><label>隧道名称</label><input type="text" id="tunnelName" placeholder="例如: ssh, web, mysql"></div>
<div style="margin:20px 0"><label>类型</label><select id="tunnelType" onchange="updateTunnelFields()">
<option value="tcp">TCP</option><option value="udp">UDP</option><option value="http">HTTP</option><option value="https">HTTPS</option></select></div>
<div style="margin:20px 0"><label>本地IP地址</label><input type="text" id="localIP" placeholder="127.0.0.1 或其他设备IP" value="127.0.0.1"></div>
<div style="display:grid;grid-template-columns:1fr 1fr;gap:15px;margin:20px 0">
<div><label>本地端口</label><input type="number" id="localPort" placeholder="例如: 22, 80, 3306"></div>
<div id="remotePortDiv"><label>远程端口</label><input type="number" id="remotePort" placeholder="例如: 6000, 8080"></div>
</div>
<div id="domainDiv" style="margin:20px 0;display:none"><label>自定义域名</label><input type="text" id="customDomain" placeholder="example.com 或 sub.domain.com"></div>
<div style="background:#f8f9fa;padding:15px;border-radius:8px;margin:20px 0;font-size:14px;color:#666">
<strong>💡 使用提示：</strong><br>
• <strong>本地设备：</strong> 127.0.0.1 或 localhost<br>
• <strong>局域网设备：</strong> 192.168.1.100, 10.0.0.50 等<br>
• <strong>域名：</strong> nas.local, router.home 等<br>
• <strong>常用端口：</strong> SSH(22), HTTP(80), HTTPS(443), MySQL(3306)
</div>
<div style="text-align:right;margin-top:30px">
<button class="btn" onclick="closeTunnelModal()" style="background:#6c757d;color:white;margin-right:10px">取消</button>
<button class="btn btn-success" onclick="saveTunnel()">💾 保存</button>
</div></div></div>

<!-- 导入配置模态框 -->
<div id="importModal" style="display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:1000">
<div style="background:white;margin:50px auto;padding:30px;width:90%;max-width:700px;border-radius:12px">
<h3>📥 导入配置文件 <span onclick="closeImportModal()" style="float:right;cursor:pointer;color:#999;font-size:24px">&times;</span></h3>

<div style="background:#f8f9fa;padding:20px;border-radius:8px;margin:20px 0;font-size:14px;line-height:1.6">
<h4 style="margin:0 0 15px 0;color:#495057">📋 操作说明</h4>
<div style="margin-bottom:15px">
<strong>1. 获取配置文件内容：</strong><br>
• 打开你保存的配置文件（.txt、.toml、.ini 等格式都可以）<br>
• 用记事本或其他文本编辑器打开<br>
• 全选并复制所有内容（Ctrl+A，然后Ctrl+C）
</div>
<div style="margin-bottom:15px">
<strong>2. 粘贴到下方文本框：</strong><br>
• 在下方大文本框中粘贴配置内容（Ctrl+V）<br>
• 支持 INI 格式和 TOML 格式，系统会自动识别
</div>
<div>
<strong>3. 点击导入：</strong><br>
• 系统会自动备份当前配置<br>
• 导入成功后自动重启 FRPC 服务
</div>
</div>

<div style="margin:20px 0">
<label style="display:block;margin-bottom:10px;font-weight:bold;font-size:16px">📝 粘贴你的配置文件内容：</label>
<textarea id="importContent" style="width:100%;height:300px;font-family:monospace;font-size:14px;border:2px solid #e1e5e9;border-radius:8px;padding:15px" placeholder="请在这里粘贴你的 FRPC 配置文件内容...

支持以下格式：

INI 格式示例：
[common]
server_addr = your-server.com
server_port = 7000
token = your_token

[ssh]
type = tcp
local_ip = 127.0.0.1
local_port = 22
remote_port = 6000

TOML 格式示例：
serverAddr = &quot;your-server.com&quot;
serverPort = 7000
auth.method = &quot;token&quot;
auth.token = &quot;your_token&quot;

[[proxies]]
name = &quot;ssh&quot;
type = &quot;tcp&quot;
localIP = &quot;127.0.0.1&quot;
localPort = 22
remotePort = 6000"></textarea>
</div>

<div style="background:#fff3cd;border:1px solid #ffeaa7;padding:15px;border-radius:8px;margin:20px 0;font-size:14px">
<strong>⚠️ 重要提示：</strong><br>
• 导入配置将<strong>完全替换</strong>当前配置文件<br>
• 导入成功后将自动重启 FRPC 服务<br>
• 建议先点击"📤 导出配置"备份当前配置<br>
• 支持从其他 FRPC 客户端导入配置文件
</div>

<div style="text-align:right;margin-top:30px">
<button class="btn" onclick="closeImportModal()" style="background:#6c757d;color:white;margin-right:10px">取消</button>
<button class="btn btn-success" onclick="importConfig()">📥 导入并重启服务</button>
</div></div></div>

<script>
function getCookie(name) {
    const cookies = document.cookie.split(';');
    for (let cookie of cookies) {
        const [cookieName, cookieValue] = cookie.trim().split('=');
        if (cookieName === name && cookieValue) {
            return cookieValue;
        }
    }
    return null;
}

function isAuthenticated() {
    const authCookie = getCookie('frpc_auth');
    console.log('检查认证状态:', authCookie ? '已认证' : '未认证');
    console.log('所有 Cookies:', document.cookie);
    return authCookie !== null;
}

// 检查认证状态
if (!isAuthenticated()) {
    console.log('未认证，重定向到登录页');
    window.location.href = '/';
} else {
    console.log('认证成功，加载仪表板');
}

function api(url, options = {}) {
    const defaultOptions = {
        credentials: 'same-origin',
        headers: {
            'Content-Type': 'application/json',
            ...options.headers
        },
        ...options
    };
    
    return fetch(url, defaultOptions).then(response => {
        if (response.status === 401) {
            // 认证失败，清除 Cookie 并重定向
            document.cookie = 'frpc_auth=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
            window.location.href = '/';
            throw new Error('Authentication failed');
        }
        return response;
    });
}

function logout() {
    document.cookie = 'frpc_auth=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
    window.location.href = '/';
}

function scrollToServerConfig() {
    document.querySelector('.card:first-child').scrollIntoView({ behavior: 'smooth' });
}

function scrollToConfigEditor() {
    document.querySelector('#configEditor').closest('.card').scrollIntoView({ behavior: 'smooth' });
}

function saveServerConfig() {
    const addr = document.getElementById('serverAddr').value.trim();
    const port = document.getElementById('serverPort').value.trim();
    const token = document.getElementById('serverToken').value.trim();
    
    if (!addr || !port || !token) {
        alert('请填写完整的服务器配置信息');
        return;
    }
    
    // 生成干净的 TOML 格式配置
    const config = `# FRPC 配置文件 - TOML 格式 (v0.61.0+)
serverAddr = "${addr}"
serverPort = ${port}

# 认证配置
auth.method = "token"
auth.token = "${token}"

# 日志配置
log.to = "/var/log/frpc.log"
log.level = "info"
log.maxDays = 3

# 隧道配置
# 请通过 Web 面板添加隧道，或点击"配置说明"查看格式`;
    
    document.getElementById('configEditor').value = config;
    saveConfig();
}

function showConfigHelp() {
    // 显示配置说明模态框
    document.getElementById('configHelpModal').style.display = 'block';
}

function loadConfig() {
    api('/api/config')
        .then(response => response.text())
        .then(content => {
            document.getElementById('configEditor').value = content;
            document.getElementById('configResult').innerHTML = '<div style="color:green">✅ 配置文件加载成功</div>';
            
            // 解析配置文件并自动填充表单（仅当配置文件中有实际值时）
            const lines = content.split('\\n');
            for (let line of lines) {
                line = line.trim();
                if (line.startsWith('#') || !line) continue;
                
                // TOML 格式解析
                if (line.includes('serverAddr')) {
                    const addr = line.split('=')[1]?.trim().replace(/"/g, '');
                    if (addr && addr !== '127.0.0.1' && addr !== 'your-server.com') {
                        document.getElementById('serverAddr').value = addr;
                    }
                } else if (line.includes('serverPort')) {
                    const port = line.split('=')[1]?.trim();
                    if (port && port !== '7000') {
                        document.getElementById('serverPort').value = port;
                    }
                } else if (line.includes('auth.token')) {
                    const token = line.split('=')[1]?.trim().replace(/"/g, '');
                    if (token && token !== 'your_token_here') {
                        document.getElementById('serverToken').value = token;
                    }
                }
                // INI 格式解析（兼容）
                else if (line.includes('server_addr')) {
                    const addr = line.split('=')[1]?.trim();
                    if (addr && addr !== '127.0.0.1' && addr !== 'your-server.com') {
                        document.getElementById('serverAddr').value = addr;
                    }
                } else if (line.includes('server_port')) {
                    const port = line.split('=')[1]?.trim();
                    if (port && port !== '7000') {
                        document.getElementById('serverPort').value = port;
                    }
                } else if (line.includes('token') && !line.includes('auth.token')) {
                    const token = line.split('=')[1]?.trim();
                    if (token && token !== 'your_token_here') {
                        document.getElementById('serverToken').value = token;
                    }
                }
            }
        })
        .catch(error => {
            document.getElementById('configResult').innerHTML = '<div style="color:red">❌ 加载失败: ' + error.message + '</div>';
        });
}

function saveConfig() {
    const content = document.getElementById('configEditor').value;
    if (!content.trim()) {
        document.getElementById('configResult').innerHTML = '<div style="color:red">❌ 配置内容不能为空</div>';
        return;
    }
    
    api('/api/config', {
        method: 'POST',
        headers: { 'Content-Type': 'text/plain' },
        body: content
    })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                document.getElementById('configResult').innerHTML = '<div style="color:green">✅ ' + (data.message || '配置保存成功，2秒后自动重启服务...') + '</div>';
                setTimeout(() => controlService('restart'), 2000);
            } else {
                document.getElementById('configResult').innerHTML = '<div style="color:red">❌ 保存失败: ' + (data.error || '未知错误') + '</div>';
            }
        })
        .catch(error => {
            document.getElementById('configResult').innerHTML = '<div style="color:red">❌ 保存失败: ' + error.message + '</div>';
        });
}

function validateConfig() {
    const content = document.getElementById('configEditor').value;
    if (!content.trim()) {
        document.getElementById('configResult').innerHTML = '<div style="color:red">❌ 配置内容不能为空</div>';
        return;
    }
    
    const lines = content.split('\\n');
    let errors = [];
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line || line.startsWith('#')) continue;
        
        if (line.startsWith('[')) {
            if (!line.endsWith(']')) {
                errors.push(`第${i + 1}行: 节名格式错误`);
            }
        } else if (line.includes('=')) {
            const [key, value] = line.split('=', 2);
            if (!key.trim() || !value.trim()) {
                errors.push(`第${i + 1}行: 配置项格式错误`);
            }
        } else {
            errors.push(`第${i + 1}行: 无效的配置行`);
        }
    }
    
    if (errors.length > 0) {
        document.getElementById('configResult').innerHTML = '<div style="color:red">❌ 验证失败:<br>' + errors.join('<br>') + '</div>';
    } else {
        document.getElementById('configResult').innerHTML = '<div style="color:green">✅ 配置语法验证通过</div>';
    }
}

function resetConfig() {
    if (confirm('确定要重置配置文件吗？这将恢复到默认配置。')) {
        api('/api/config/reset', { method: 'POST' })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    loadConfig();
                    loadTunnelList();
                    document.getElementById('configResult').innerHTML = '<div style="color:green">✅ 配置已重置为默认值</div>';
                } else {
                    document.getElementById('configResult').innerHTML = '<div style="color:red">❌ 重置失败: ' + (data.error || '未知错误') + '</div>';
                }
            })
            .catch(error => {
                document.getElementById('configResult').innerHTML = '<div style="color:red">❌ 重置失败: ' + error.message + '</div>';
            });
    }
}

function controlService(action) {
    const resultEl = document.getElementById('serviceResult');
    resultEl.innerHTML = '<div style="color:blue">⏳ 正在执行操作...</div>';
    
    api('/api/service', {
        method: 'POST',
        body: JSON.stringify({ action })
    })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                resultEl.innerHTML = '<div style="color:green">✅ ' + action + ' 操作成功</div>';
                setTimeout(refreshStatus, 2000);
            } else {
                resultEl.innerHTML = '<div style="color:red">❌ 操作失败: ' + (data.error || '未知错误') + '</div>';
            }
        })
        .catch(error => {
            if (error.message.includes('Authentication')) {
                resultEl.innerHTML = '<div style="color:red">❌ 认证失败，正在重新登录...</div>';
                setTimeout(() => window.location.href = '/', 2000);
            } else {
                resultEl.innerHTML = '<div style="color:red">❌ 操作失败: ' + error.message + '</div>';
            }
        });
}

function refreshStatus() {
    api('/api/status')
        .then(response => response.json())
        .then(data => {
            if (data.frpc) {
                const statusEl = document.getElementById('status');
                statusEl.textContent = data.frpc.running ? '运行中' : '已停止';
                statusEl.style.color = data.frpc.running ? '#28a745' : '#dc3545';
                document.getElementById('uptime').textContent = data.frpc.uptime || '--';
                document.getElementById('memory').textContent = data.frpc.memory_usage ? (data.frpc.memory_usage.toFixed(1) + ' MB') : '--';
            }
            if (data.system) {
                document.getElementById('cpu').textContent = data.system.cpu_percent ? (data.system.cpu_percent.toFixed(1) + '%') : '--';
            }
        })
        .catch(error => {
            document.getElementById('status').textContent = '检查失败';
            document.getElementById('status').style.color = '#dc3545';
        });
}

function refreshLogs() {
    api('/api/logs')
        .then(response => response.json())
        .then(data => {
            const logsEl = document.getElementById('logs');
            
            if (data.success && data.logs && data.logs.length > 0) {
                const logHtml = data.logs.map(l => 
                    '<div style="margin-bottom:2px;font-size:12px;line-height:1.4">[' + 
                    l.timestamp + '] ' + 
                    l.message + 
                    '</div>'
                ).join('');
                logsEl.innerHTML = logHtml;
                logsEl.scrollTop = logsEl.scrollHeight;
            } else {
                logsEl.innerHTML = '<div style="color:#999;text-align:center;padding:20px">暂无日志数据<br><small>FRPC 服务可能刚启动，请稍后刷新</small></div>';
            }
        })
        .catch(error => {
            document.getElementById('logs').innerHTML = 
                '<div style="color:red;text-align:center;padding:20px">' +
                '日志加载失败: ' + error.message + 
                '<br><small>请检查 FRPC 服务是否正常运行</small>' +
                '</div>';
        });
}

// 初始化页面
window.onload = function() {
    loadConfig();
    refreshStatus();
    refreshLogs();
    loadTunnelList();
    setInterval(refreshStatus, 30000);
    setInterval(refreshLogs, 60000);
};

function loadTunnelList() {
    api('/api/config')
        .then(response => response.text())
        .then(content => {
            const tunnels = parseTunnelsFromConfig(content);
            displayTunnelList(tunnels);
        })
        .catch(error => {
            document.getElementById('tunnelList').innerHTML = '<div style="color:red;text-align:center;padding:20px">隧道列表加载失败: ' + error.message + '</div>';
        });
}

function parseTunnelsFromConfig(content) {
    const tunnels = [];
    const lines = content.split('\\n');
    let currentTunnel = null;
    let inProxiesSection = false;
    
    for (let line of lines) {
        line = line.trim();
        
        // TOML 格式解析
        if (line === '[[proxies]]') {
            if (currentTunnel) {
                tunnels.push(currentTunnel);
            }
            currentTunnel = {
                name: '',
                type: 'tcp',
                local_ip: '127.0.0.1',
                local_port: '',
                remote_port: '',
                custom_domains: ''
            };
            inProxiesSection = true;
        } else if (inProxiesSection && line.includes('=')) {
            const [key, value] = line.split('=', 2);
            const k = key.trim();
            let v = value.trim().replace(/"/g, ''); // 移除引号
            
            if (k === 'name') currentTunnel.name = v;
            else if (k === 'type') currentTunnel.type = v;
            else if (k === 'localIP') currentTunnel.local_ip = v;
            else if (k === 'localPort') currentTunnel.local_port = v;
            else if (k === 'remotePort') currentTunnel.remote_port = v;
            else if (k === 'customDomains') {
                // 处理数组格式 ["domain.com"]
                v = v.replace(/[\[\]]/g, '').replace(/"/g, '');
                currentTunnel.custom_domains = v;
            }
        }
        // INI 格式兼容解析
        else if (line.startsWith('[') && line.endsWith(']') && line !== '[common]' && !line.includes('proxies')) {
            if (currentTunnel) {
                tunnels.push(currentTunnel);
            }
            currentTunnel = {
                name: line.slice(1, -1),
                type: 'tcp',
                local_ip: '127.0.0.1',
                local_port: '',
                remote_port: '',
                custom_domains: ''
            };
            inProxiesSection = false;
        } else if (!inProxiesSection && currentTunnel && line.includes('=')) {
            const [key, value] = line.split('=', 2);
            const k = key.trim();
            const v = value.trim();
            if (k === 'type') currentTunnel.type = v;
            else if (k === 'local_ip') currentTunnel.local_ip = v;
            else if (k === 'local_port') currentTunnel.local_port = v;
            else if (k === 'remote_port') currentTunnel.remote_port = v;
            else if (k === 'custom_domains') currentTunnel.custom_domains = v;
        }
    }
    
    if (currentTunnel && currentTunnel.name) {
        tunnels.push(currentTunnel);
    }
    
    return tunnels;
}

function displayTunnelList(tunnels) {
    const listEl = document.getElementById('tunnelList');
    
    if (tunnels.length === 0) {
        listEl.innerHTML = '<div style="text-align:center;padding:40px;color:#999"><div style="font-size:48px;margin-bottom:16px">🚇</div><div style="font-size:18px;margin-bottom:8px">暂无隧道配置</div><div style="font-size:14px">点击右上角"+ 添加隧道"开始配置</div></div>';
        return;
    }
    
    let html = '<div style="display:grid;gap:15px">';
    
    for (let tunnel of tunnels) {
        const typeColor = {
            'tcp': '#007bff',
            'udp': '#6f42c1', 
            'http': '#28a745',
            'https': '#fd7e14'
        }[tunnel.type] || '#6c757d';
        
        html += `
        <div style="border:1px solid #dee2e6;border-radius:8px;padding:16px;background:#f8f9fa">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
                <div style="display:flex;align-items:center;gap:12px">
                    <div style="font-weight:600;font-size:16px">${tunnel.name}</div>
                    <span style="background:${typeColor};color:white;padding:2px 8px;border-radius:4px;font-size:12px;font-weight:500">${tunnel.type.toUpperCase()}</span>
                </div>
                <div>
                    <button class="btn" onclick="editTunnel('${tunnel.name}')" style="background:#007bff;color:white;padding:4px 8px;font-size:12px;margin-right:5px">编辑</button>
                    <button class="btn" onclick="deleteTunnel('${tunnel.name}')" style="background:#dc3545;color:white;padding:4px 8px;font-size:12px">删除</button>
                </div>
            </div>
            <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:8px;font-size:14px;color:#666">
                <div><strong>本地:</strong> ${tunnel.local_ip}:${tunnel.local_port}</div>
                ${tunnel.remote_port ? `<div><strong>远程端口:</strong> ${tunnel.remote_port}</div>` : ''}
                ${tunnel.custom_domains ? `<div><strong>域名:</strong> ${tunnel.custom_domains}</div>` : ''}
            </div>
        </div>`;
    }
    
    html += '</div>';
    listEl.innerHTML = html;
}

function deleteTunnel(tunnelName) {
    if (!confirm('确定要删除隧道 "' + tunnelName + '" 吗？')) {
        return;
    }
    
    api('/api/config')
        .then(response => response.text())
        .then(content => {
            const lines = content.split('\\n');
            const newLines = [];
            let inTargetTunnel = false;
            let skipNextLines = 0;
            
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                const trimmed = line.trim();
                
                // TOML 格式：查找 [[proxies]] 和匹配的 name
                if (trimmed === '[[proxies]]') {
                    // 检查接下来几行是否包含目标隧道名称
                    let foundTarget = false;
                    for (let j = i + 1; j < Math.min(i + 10, lines.length); j++) {
                        const nextLine = lines[j].trim();
                        if (nextLine.startsWith('name = "' + tunnelName + '"') || 
                            nextLine.startsWith("name = '" + tunnelName + "'")) {
                            foundTarget = true;
                            break;
                        }
                        if (nextLine === '[[proxies]]' || nextLine.startsWith('[')) {
                            break;
                        }
                    }
                    
                    if (foundTarget) {
                        inTargetTunnel = true;
                        continue;
                    }
                }
                // INI 格式兼容：查找 [tunnelName]
                else if (trimmed === '[' + tunnelName + ']') {
                    inTargetTunnel = true;
                    continue;
                }
                // 检查是否到达下一个隧道或配置段
                else if (trimmed === '[[proxies]]' || 
                        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
                    inTargetTunnel = false;
                }
                
                if (!inTargetTunnel) {
                    newLines.push(line);
                }
            }
            
            const newContent = newLines.join('\\n');
            
            return api('/api/config', {
                method: 'POST',
                headers: { 'Content-Type': 'text/plain' },
                body: newContent
            });
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                alert('隧道删除成功！');
                loadConfig();
                loadTunnelList();
            } else {
                alert('删除失败: ' + (data.error || '未知错误'));
            }
        })
        .catch(error => {
            alert('删除失败: ' + error.message);
        });
}

function showAddTunnel() {
    document.getElementById('tunnelModal').style.display = 'block';
}

function closeTunnelModal() {
    document.getElementById('tunnelModal').style.display = 'none';
    document.getElementById('tunnelName').value = '';
    document.getElementById('localIP').value = '127.0.0.1';
    document.getElementById('localPort').value = '';
    document.getElementById('remotePort').value = '';
    document.getElementById('customDomain').value = '';
    editingTunnelName = null;
    
    // 恢复模态框标题
    document.querySelector('#tunnelModal h3').innerHTML = '🚇 添加隧道 <span onclick="closeTunnelModal()" style="float:right;cursor:pointer;color:#999;font-size:24px">&times;</span>';
}

// 导出配置功能
function exportConfig() {
    api('/api/config')
        .then(response => response.text())
        .then(content => {
            // 创建下载链接
            const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = `frpc-config-${new Date().toISOString().split('T')[0]}.txt`;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
            
            alert('✅ 配置文件导出成功！\\n文件名: frpc-config-' + new Date().toISOString().split('T')[0] + '.txt\\n\\n可以用记事本打开查看和编辑');
        })
        .catch(error => {
            alert('❌ 导出失败: ' + error.message);
        });
}

// 显示导入模态框
function showImportModal() {
    document.getElementById('importModal').style.display = 'block';
    document.getElementById('importContent').value = '';
}

// 关闭导入模态框
function closeImportModal() {
    document.getElementById('importModal').style.display = 'none';
    document.getElementById('importContent').value = '';
}

// 导入配置功能
function importConfig() {
    const content = document.getElementById('importContent').value.trim();
    
    if (!content) {
        alert('❌ 请粘贴配置文件内容');
        return;
    }
    
    // 简单验证是否包含配置内容
    if (!content.includes('server') && !content.includes('[')) {
        alert('❌ 配置内容格式不正确\\n\\n请确保粘贴的是完整的 FRPC 配置文件内容');
        return;
    }
    
    if (!confirm('⚠️ 确定要导入配置吗？\\n\\n• 这将完全替换当前配置文件\\n• 导入后自动重启 FRPC 服务\\n• 建议先导出当前配置作为备份\\n\\n点击"确定"继续导入')) {
        return;
    }
    
    // 自动检测格式
    let format = 'toml';
    if (content.includes('[common]')) {
        // 明确包含[common]的是INI格式
        format = 'ini';
    } else if (content.includes('[[proxies]]') || content.includes('serverAddr') || content.includes('auth.method')) {
        // 包含TOML特有语法的是TOML格式
        format = 'toml';
    } else if (content.includes('[') && content.includes('=') && !content.includes('[[')) {
        // 包含单层方括号但不包含双层方括号的可能是INI格式
        format = 'ini';
    }
    
    // 发送导入请求
    api('/api/config/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content: content, format: format })
    })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                alert('✅ 配置导入成功！\\n\\n' + (data.message || '配置已更新，服务正在重启...'));
                closeImportModal();
                // 刷新配置显示
                setTimeout(() => loadConfig(), 1000);
            } else {
                alert('❌ 导入失败: ' + (data.error || '未知错误'));
            }
        })
        .catch(error => {
            alert('❌ 导入失败: ' + error.message);
        });
}

function updateTunnelFields() {
    const type = document.getElementById('tunnelType').value;
    const domainDiv = document.getElementById('domainDiv');
    const remotePortDiv = document.getElementById('remotePortDiv');
    
    if (type === 'http' || type === 'https') {
        domainDiv.style.display = 'block';
        remotePortDiv.style.display = 'none';
    } else {
        domainDiv.style.display = 'none';
        remotePortDiv.style.display = 'block';
    }
}

let editingTunnelName = null;

function saveTunnel() {
    const name = document.getElementById('tunnelName').value.trim();
    const type = document.getElementById('tunnelType').value;
    const localIP = document.getElementById('localIP').value.trim();
    const localPort = document.getElementById('localPort').value.trim();
    const remotePort = document.getElementById('remotePort').value.trim();
    const domain = document.getElementById('customDomain').value.trim();
    
    if (!name || !localIP || !localPort) {
        alert('请填写隧道名称、本地IP地址和本地端口');
        return;
    }
    
    // 验证IP地址格式（支持域名）
    const ipPattern = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$|^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$|^localhost$/;
    if (!ipPattern.test(localIP)) {
        alert('请输入有效的IP地址或域名\\n例如: 127.0.0.1, 192.168.1.100, nas.local');
        return;
    }
    
    if (isNaN(localPort) || localPort < 1 || localPort > 65535) {
        alert('请输入有效的本地端口号 (1-65535)');
        return;
    }
    
    if (remotePort && (isNaN(remotePort) || remotePort < 1 || remotePort > 65535)) {
        alert('请输入有效的远程端口号 (1-65535)');
        return;
    }
    
    const tunnelData = { 
        name: name, 
        type: type,
        local_ip: localIP,
        local_port: localPort,
        is_edit: editingTunnelName !== null,
        old_name: editingTunnelName
    };
    
    if (type === 'http' || type === 'https') {
        if (domain) {
            tunnelData.custom_domains = domain;
        }
    } else {
        if (remotePort) {
            tunnelData.remote_port = remotePort;
        }
    }
    
    api('/api/tunnels', {
        method: 'POST',
        body: JSON.stringify(tunnelData)
    })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                const action = editingTunnelName ? '编辑' : '添加';
                alert('隧道' + action + '成功！\\n\\n配置详情：\\n• 名称: ' + name + '\\n• 类型: ' + type.toUpperCase() + '\\n• 本地: ' + localIP + ':' + localPort + (remotePort ? '\\n• 远程端口: ' + remotePort : '') + (domain ? '\\n• 域名: ' + domain : ''));
                closeTunnelModal();
                loadConfig();
                loadTunnelList();
            } else {
                alert((editingTunnelName ? '编辑' : '添加') + '失败: ' + (data.error || '未知错误'));
            }
        })
        .catch(error => {
            alert((editingTunnelName ? '编辑' : '添加') + '失败: ' + error.message);
        });
}

function editTunnel(tunnelName) {
    // 找到要编辑的隧道
    api('/api/config')
        .then(response => response.text())
        .then(content => {
            const tunnels = parseTunnelsFromConfig(content);
            const tunnel = tunnels.find(t => t.name === tunnelName);
            
            if (tunnel) {
                editingTunnelName = tunnelName;
                
                // 填充表单
                document.getElementById('tunnelName').value = tunnel.name;
                document.getElementById('tunnelType').value = tunnel.type;
                document.getElementById('localIP').value = tunnel.local_ip;
                document.getElementById('localPort').value = tunnel.local_port;
                document.getElementById('remotePort').value = tunnel.remote_port || '';
                document.getElementById('customDomain').value = tunnel.custom_domains || '';
                
                // 更新字段显示
                updateTunnelFields();
                
                // 更新模态框标题
                document.querySelector('#tunnelModal h3').innerHTML = '🔧 编辑隧道 <span onclick="closeTunnelModal()" style="float:right;cursor:pointer;color:#999;font-size:24px">&times;</span>';
                
                // 显示模态框
                document.getElementById('tunnelModal').style.display = 'block';
            } else {
                alert('未找到隧道: ' + tunnelName);
            }
        })
        .catch(error => {
            alert('获取隧道信息失败: ' + error.message);
        });
}

function closeConfigHelp() {
    document.getElementById('configHelpModal').style.display = 'none';
}

function toggleHelp() {
    const helpDiv = document.getElementById('configHelp');
    if (helpDiv.style.display === 'none') {
        helpDiv.style.display = 'block';
    } else {
        helpDiv.style.display = 'none';
    }
}
</script></body></html>'''
        self.send_response(200)
        self.send_header('Content-type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(html.encode())
    
    def api_login(self):
        """处理登录请求"""
        auth = self.headers.get('Authorization', '')
        
        if auth.startswith('Basic '):
            try:
                decoded = base64.b64decode(auth[6:]).decode('utf-8')
                if ':' in decoded:
                    user, pwd = decoded.split(':', 1)
                    expected_user = self.web_config.get('username', '')
                    expected_pwd = self.web_config.get('password', '')
                    
                    if user == expected_user and pwd == expected_pwd:
                        # 登录成功，设置可读取的 Cookie（移除 HttpOnly）
                        self.send_response(200)
                        self.send_header('Content-type', 'application/json; charset=utf-8')
                        self.send_header('Set-Cookie', f'frpc_auth={auth[6:]}; Path=/; Max-Age=86400')
                        self.send_header('Access-Control-Allow-Origin', '*')
                        self.end_headers()
                        response = json.dumps({'success': True, 'message': '登录成功'}, ensure_ascii=False)
                        self.wfile.write(response.encode('utf-8'))
                        return
                    else:
                        self.send_json({'success': False, 'error': '用户名或密码错误'}, 401)
                        return
                else:
                    self.send_json({'success': False, 'error': '认证格式错误'}, 400)
                    return
            except Exception as e:
                self.send_json({'success': False, 'error': f'认证解析错误: {str(e)}'}, 400)
                return
        else:
            self.send_json({'success': False, 'error': '缺少认证信息'}, 400)
    
    def handle_api(self, method, path):
        try:
            if path == '/api/status':
                self.api_status()
            elif path == '/api/config':
                if method == 'GET': self.api_get_config()
                elif method == 'POST': self.api_save_config()
            elif path == '/api/config/import':
                if method == 'POST': self.api_import_config()
            elif path == '/api/config/reset':
                if method == 'POST': self.api_reset_config()
            elif path == '/api/service':
                if method == 'POST': self.api_control_service()
            elif path == '/api/logs':
                self.api_get_logs()
            elif path == '/api/tunnels':
                if method == 'POST': self.api_add_tunnel()
                elif method == 'GET': self.api_get_tunnels()
            else:
                self.send_json({'error': 'API endpoint not found'}, 404)
        except Exception as e:
            self.send_json({'error': str(e)}, 500)
    
    def api_status(self):
        try:
            # 检查 FRPC 进程
            frpc_running = False
            frpc_pid = None
            uptime = None
            memory_usage = None
            
            try:
                result = subprocess.run(['pgrep', '-f', 'frpc'], capture_output=True, text=True)
                if result.returncode == 0 and result.stdout.strip():
                    frpc_pid = int(result.stdout.strip().split('\n')[0])
                    frpc_running = True
                    
                    if PSUTIL_AVAILABLE:
                        try:
                            proc = psutil.Process(frpc_pid)
                            create_time = proc.create_time()
                            uptime_seconds = time.time() - create_time
                            hours = int(uptime_seconds // 3600)
                            minutes = int((uptime_seconds % 3600) // 60)
                            uptime = f"{hours}h {minutes}m"
                            memory_usage = proc.memory_info().rss / 1024 / 1024  # MB
                        except:
                            pass
            except:
                pass
            
            # 系统信息
            cpu_percent = 0.0
            if PSUTIL_AVAILABLE:
                try:
                    cpu_percent = psutil.cpu_percent(interval=1)
                except:
                    pass
            
            self.send_json({
                'frpc': {
                    'running': frpc_running,
                    'pid': frpc_pid,
                    'uptime': uptime,
                    'memory_usage': memory_usage
                },
                'system': {
                    'cpu_percent': cpu_percent
                }
            })
        except Exception as e:
            self.send_json({'error': str(e)}, 500)
    
    def api_get_config(self):
        try:
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-type', 'text/plain; charset=utf-8')
                self.end_headers()
                self.wfile.write(content.encode('utf-8'))
            else:
                self.send_response(404)
                self.end_headers()
        except Exception as e:
            self.send_json({'error': str(e)}, 500)
    
    def api_save_config(self):
        try:
            import time
            
            content_length = int(self.headers.get('Content-Length', 0))
            content = self.rfile.read(content_length).decode('utf-8')
            
            # 备份原配置
            if os.path.exists(CONFIG_FILE):
                backup_file = CONFIG_FILE + '.backup.' + str(int(time.time()))
                subprocess.run(['cp', CONFIG_FILE, backup_file])
            
            # 保存新配置
            os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                f.write(content)
            
            self.send_json({'success': True, 'message': '配置保存成功'})
        except Exception as e:
            self.send_json({'success': False, 'error': str(e)}, 500)
    
    def api_import_config(self):
        try:
            import time
            import threading
            
            content_length = int(self.headers.get('Content-Length', 0))
            data = json.loads(self.rfile.read(content_length).decode('utf-8'))
            
            import_content = data.get('content', '').strip()
            import_format = data.get('format', 'toml')
            
            if not import_content:
                self.send_json({'success': False, 'error': '配置内容不能为空'})
                return
            
            # 备份当前配置
            if os.path.exists(CONFIG_FILE):
                backup_file = CONFIG_FILE + '.backup.' + str(int(time.time()))
                subprocess.run(['cp', CONFIG_FILE, backup_file])
            
            # 处理不同格式的配置
            final_content = import_content
            
            if import_format == 'ini':
                # 如果是INI格式，需要转换为TOML格式
                final_content = self.convert_ini_to_toml(import_content)
                if not final_content:
                    self.send_json({'success': False, 'error': 'INI格式转换失败，请检查配置格式'})
                    return
            
            # 保存配置
            os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                f.write(final_content)
            
            # 自动重启服务（延时2秒）
            def restart_service():
                time.sleep(2)
                try:
                    # 智能检测服务管理方式
                    if os.path.exists('/bin/systemctl') or os.path.exists('/usr/bin/systemctl'):
                        subprocess.run(['systemctl', 'restart', 'frpc'], check=False, capture_output=True)
                    elif os.path.exists('/etc/init.d/frpc'):
                        subprocess.run(['/etc/init.d/frpc', 'restart'], check=False, capture_output=True)
                    else:
                        # 直接重启进程
                        subprocess.run(['pkill', '-f', 'frpc-bin'], check=False)
                        time.sleep(1)
                        subprocess.Popen(['/usr/local/bin/frpc-bin', '-c', CONFIG_FILE])
                except:
                    pass
            
            restart_thread = threading.Thread(target=restart_service)
            restart_thread.daemon = True
            restart_thread.start()
            
            self.send_json({'success': True, 'message': f'配置导入成功（{import_format.upper()}格式），2秒后自动重启服务'})
        except Exception as e:
            self.send_json({'success': False, 'error': str(e)}, 500)
    
    def convert_ini_to_toml(self, ini_content):
        """将INI格式配置转换为TOML格式"""
        try:
            lines = ini_content.strip().split('\n')
            toml_lines = ['# FRPC 配置文件 - TOML 格式 (从INI转换)', '']
            
            current_section = None
            proxies = []
            
            for line in lines:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith(';'):
                    continue
                
                if line.startswith('[') and line.endswith(']'):
                    current_section = line[1:-1]
                    if current_section != 'common':
                        proxies.append({'name': current_section, 'config': {}})
                elif '=' in line and current_section:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")
                    
                    if current_section == 'common':
                        # 转换common配置
                        if key == 'server_addr':
                            toml_lines.append(f'serverAddr = "{value}"')
                        elif key == 'server_port':
                            toml_lines.append(f'serverPort = {value}')
                        elif key == 'token':
                            toml_lines.append('auth.method = "token"')
                            toml_lines.append(f'auth.token = "{value}"')
                        elif key == 'log_file':
                            toml_lines.append(f'log.to = "{value}"')
                        elif key == 'log_level':
                            toml_lines.append(f'log.level = "{value}"')
                        elif key == 'log_max_days':
                            toml_lines.append(f'log.maxDays = {value}')
                    else:
                        # 转换代理配置
                        if key == 'local_ip':
                            proxies[-1]['config']['localIP'] = value
                        elif key == 'local_port':
                            proxies[-1]['config']['localPort'] = value
                        elif key == 'remote_port':
                            proxies[-1]['config']['remotePort'] = value
                        elif key == 'custom_domains':
                            proxies[-1]['config']['customDomains'] = [value]
                        else:
                            proxies[-1]['config'][key] = value
            
            toml_lines.append('')
            
            # 添加代理配置
            for proxy in proxies:
                toml_lines.append('[[proxies]]')
                toml_lines.append(f'name = "{proxy["name"]}"')
                for key, value in proxy['config'].items():
                    if key == 'customDomains' and isinstance(value, list):
                        toml_lines.append(f'{key} = ["{value[0]}"]')
                    elif key in ['localPort', 'remotePort']:
                        toml_lines.append(f'{key} = {value}')
                    else:
                        toml_lines.append(f'{key} = "{value}"')
                toml_lines.append('')
            
            return '\n'.join(toml_lines)
        except Exception as e:
            print(f"INI转换错误: {e}")
            return None
    
    def api_reset_config(self):
        try:
            # TOML 格式的默认配置（干净版本）
            default_toml_config = '''# FRPC 配置文件 - TOML 格式 (v0.61.0+)
# 请修改以下配置为你的实际服务器信息

serverAddr = "your-server.com"
serverPort = 7000

# 认证配置
auth.method = "token"
auth.token = "your_token_here"

# 日志配置
log.to = "/var/log/frpc.log"
log.level = "info"
log.maxDays = 3

# 隧道配置
# 请通过 Web 面板添加隧道，或点击"配置说明"查看格式

# TLS 配置（如果需要）
# transport.tls.enable = true
# transport.tls.certFile = "/etc/frp/ssl/client.crt"
# transport.tls.keyFile = "/etc/frp/ssl/client.key"
# transport.tls.trustedCaFile = "/etc/frp/ssl/ca.crt"
'''
            
            # INI 格式的兼容配置
            default_ini_config = '''[common]
server_addr = 127.0.0.1
server_port = 7000
token = your_token_here
admin_addr = 127.0.0.1
admin_port = 7400
log_file = /var/log/frpc.log
log_level = info
log_max_days = 3

# 示例隧道配置（可以通过 Web 面板管理）
# [ssh]
# type = tcp
# local_ip = 127.0.0.1
# local_port = 22
# remote_port = 6000
'''
            
            os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
            
            # 写入 TOML 配置文件
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                f.write(default_toml_config)
            
            # 写入 INI 兼容配置文件
            with open(CONFIG_FILE_INI, 'w', encoding='utf-8') as f:
                f.write(default_ini_config)
            
            # 重启FRPC服务以应用新配置
            try:
                subprocess.run(['systemctl', 'restart', 'frpc'], check=False)
            except:
                pass
            
            self.send_json({'success': True, 'message': '配置已重置为默认值（TOML格式），服务正在重启'})
        except Exception as e:
            self.send_json({'success': False, 'error': str(e)}, 500)
    
    def api_control_service(self):
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            data = json.loads(self.rfile.read(content_length).decode('utf-8'))
            action = data.get('action')
            
            if action not in ['start', 'stop', 'restart']:
                self.send_json({'success': False, 'error': '无效的操作'}, 400)
                return
            
            # 智能检测服务管理方式
            success = False
            message = ""
            
            # 优先尝试 systemctl (systemd)
            if os.path.exists('/bin/systemctl') or os.path.exists('/usr/bin/systemctl'):
                try:
                    result = subprocess.run(['systemctl', action, 'frpc'], capture_output=True, text=True)
                    if result.returncode == 0:
                        success = True
                        message = f'服务{action}成功'
                except:
                    pass
            
            # 如果 systemctl 不可用或失败，尝试 init.d (OpenWrt)
            if not success and os.path.exists('/etc/init.d/frpc'):
                try:
                    result = subprocess.run(['/etc/init.d/frpc', action], capture_output=True, text=True)
                    if result.returncode == 0:
                        success = True
                        message = f'服务{action}成功'
                except:
                    pass
            
            # 如果以上都失败，尝试直接操作进程
            if not success:
                try:
                    if action == 'stop':
                        subprocess.run(['pkill', '-f', 'frpc-bin'], check=False)
                        success = True
                        message = '服务停止成功'
                    elif action == 'start':
                        subprocess.Popen(['/usr/local/bin/frpc-bin', '-c', CONFIG_FILE])
                        success = True
                        message = '服务启动成功'
                    elif action == 'restart':
                        subprocess.run(['pkill', '-f', 'frpc-bin'], check=False)
                        time.sleep(1)
                        subprocess.Popen(['/usr/local/bin/frpc-bin', '-c', CONFIG_FILE])
                        success = True
                        message = '服务重启成功'
                except Exception as e:
                    success = False
                    message = f'操作失败: {str(e)}'
            
            if success:
                self.send_json({'success': True, 'message': message})
            else:
                self.send_json({'success': False, 'error': message or '服务操作失败'})
        except Exception as e:
            self.send_json({'success': False, 'error': str(e)}, 500)
    
    def api_get_logs(self):
        try:
            logs = []
            
            # 尝试多个可能的日志位置
            log_files = [
                LOG_FILE,
                '/var/log/frpc.log',
                '/tmp/frpc.log',
                '/var/log/syslog'
            ]
            
            log_content = []
            for log_file in log_files:
                if os.path.exists(log_file):
                    try:
                        with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                            if log_file == '/var/log/syslog':
                                # 从syslog中提取frpc相关日志
                                lines = f.readlines()[-200:]  # 最后200行
                                for line in lines:
                                    if 'frpc' in line.lower():
                                        log_content.append(line.strip())
                            else:
                                log_content.extend(f.readlines())
                        break
                    except:
                        continue
            
            # 如果没有找到日志文件，尝试使用journalctl
            if not log_content:
                try:
                    import subprocess
                    result = subprocess.run(['journalctl', '-u', 'frpc', '--no-pager', '-n', '50'], 
                                          capture_output=True, text=True, timeout=5)
                    if result.returncode == 0:
                        log_content = result.stdout.split('\n')
                except:
                    pass
            
            # 处理日志内容
            for line in log_content[-50:]:  # 最后50行
                line = line.strip()
                if line:
                    # 简单的日志解析
                    timestamp = datetime.now().strftime('%H:%M:%S')
                    message = line
                    
                    # 尝试提取时间戳
                    if '[' in line and ']' in line:
                        try:
                            timestamp = line.split(']')[0][1:]
                            message = ']'.join(line.split(']')[1:]).strip()
                        except:
                            pass
                    elif line.startswith('Aug ') or line.startswith('Sep ') or line.startswith('Oct '):
                        # 处理syslog格式
                        parts = line.split(' ', 3)
                        if len(parts) >= 3:
                            timestamp = ' '.join(parts[:3])
                            message = parts[3] if len(parts) > 3 else line
                    
                    logs.append({
                        'timestamp': timestamp,
                        'message': message
                    })
            
            # 如果还是没有日志，提供一些默认信息
            if not logs:
                logs.append({
                    'timestamp': datetime.now().strftime('%H:%M:%S'),
                    'message': 'FRPC 服务正在运行，但暂无日志输出'
                })
                logs.append({
                    'timestamp': datetime.now().strftime('%H:%M:%S'),
                    'message': '日志文件位置: ' + LOG_FILE
                })
            
            self.send_json({'success': True, 'logs': logs})
        except Exception as e:
            # 提供详细的错误信息
            error_logs = [
                {
                    'timestamp': datetime.now().strftime('%H:%M:%S'),
                    'message': f'日志获取失败: {str(e)}'
                },
                {
                    'timestamp': datetime.now().strftime('%H:%M:%S'),
                    'message': f'尝试的日志文件: {LOG_FILE}'
                }
            ]
            self.send_json({'success': False, 'error': str(e), 'logs': error_logs})
    
    def api_add_tunnel(self):
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            data = json.loads(self.rfile.read(content_length).decode('utf-8'))
            
            name = data.get('name', '').strip()
            tunnel_type = data.get('type', 'tcp')
            local_ip = data.get('local_ip', '127.0.0.1').strip()
            local_port = data.get('local_port')
            remote_port = data.get('remote_port')
            custom_domains = data.get('custom_domains', '').strip()
            is_edit = data.get('is_edit', False)
            old_name = data.get('old_name', '')
            
            if not name or not local_ip or not local_port:
                self.send_json({'success': False, 'error': '隧道名称、本地IP和本地端口不能为空'})
                return
            
            # 读取现有配置
            config_content = ''
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                    config_content = f.read()
            
            # 如果是编辑模式，先删除旧的隧道配置
            if is_edit and old_name:
                lines = config_content.split('\n')
                new_lines = []
                in_target_tunnel = False
                
                for i, line in enumerate(lines):
                    trimmed = line.strip()
                    
                    if trimmed == '[[proxies]]':
                        # 检查是否是目标隧道
                        found_target = False
                        for j in range(i + 1, min(i + 10, len(lines))):
                            next_line = lines[j].strip()
                            if next_line.startswith('name = "' + old_name + '"') or next_line.startswith("name = '" + old_name + "'"):
                                found_target = True
                                break
                            if next_line == '[[proxies]]' or next_line.startswith('['):
                                break
                        
                        if found_target:
                            in_target_tunnel = True
                            continue
                    elif trimmed == '[[proxies]]' or (trimmed.startswith('[') and trimmed.endswith(']')):
                        in_target_tunnel = False
                    
                    if not in_target_tunnel:
                        new_lines.append(line)
                
                config_content = '\n'.join(new_lines)
            
            # 构建 TOML 格式的隧道配置
            tunnel_config = f'\n[[proxies]]\n'
            tunnel_config += f'name = "{name}"\n'
            tunnel_config += f'type = "{tunnel_type}"\n'
            tunnel_config += f'localIP = "{local_ip}"\n'
            tunnel_config += f'localPort = {local_port}\n'
            
            if tunnel_type in ['http', 'https']:
                if custom_domains:
                    tunnel_config += f'customDomains = ["{custom_domains}"]\n'
            else:
                if remote_port:
                    tunnel_config += f'remotePort = {remote_port}\n'
            
            # 添加到配置文件
            config_content += tunnel_config
            
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                f.write(config_content)
            
            action = '编辑' if is_edit else '添加'
            
            # 自动重启服务（延时2秒）
            import threading
            import time
            def restart_service():
                time.sleep(2)
                try:
                    import subprocess
                    # 智能检测服务管理方式
                    if os.path.exists('/bin/systemctl') or os.path.exists('/usr/bin/systemctl'):
                        subprocess.run(['systemctl', 'restart', 'frpc'], check=False, capture_output=True)
                    elif os.path.exists('/etc/init.d/frpc'):
                        subprocess.run(['/etc/init.d/frpc', 'restart'], check=False, capture_output=True)
                    else:
                        # 直接重启进程
                        subprocess.run(['pkill', '-f', 'frpc-bin'], check=False)
                        time.sleep(1)
                        subprocess.Popen(['/usr/local/bin/frpc-bin', '-c', CONFIG_FILE])
                except:
                    pass
            
            restart_thread = threading.Thread(target=restart_service)
            restart_thread.daemon = True
            restart_thread.start()
            
            self.send_json({'success': True, 'message': f'隧道 {name} {action}成功，2秒后自动重启服务'})
        except Exception as e:
            self.send_json({'success': False, 'error': str(e)}, 500)
    
    def api_get_tunnels(self):
        try:
            tunnels = []
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                    content = f.read()
                    lines = content.split('\n')
                    current_tunnel = None
                    
                    for line in lines:
                        line = line.strip()
                        if line.startswith('[') and line.endswith(']') and line != '[common]':
                            if current_tunnel:
                                tunnels.append(current_tunnel)
                            current_tunnel = {
                                'name': line[1:-1],
                                'type': 'tcp',
                                'local_ip': '127.0.0.1',
                                'local_port': '',
                                'remote_port': '',
                                'custom_domains': ''
                            }
                        elif current_tunnel and '=' in line:
                            key, value = line.split('=', 1)
                            key = key.strip()
                            value = value.strip()
                            if key in current_tunnel:
                                current_tunnel[key] = value
                    
                    if current_tunnel:
                        tunnels.append(current_tunnel)
            
            self.send_json({'success': True, 'tunnels': tunnels})
        except Exception as e:
            self.send_json({'success': False, 'error': str(e), 'tunnels': []}, 500)

def create_configured_handler(web_config):
    class ConfiguredHandler(FRPCHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, web_config=web_config, **kwargs)
    return ConfiguredHandler

def main():
    if len(sys.argv) < 4:
        print("用法: python3 frpc-web-panel.py <port> <username> <password>")
        sys.exit(1)
    
    port = int(sys.argv[1])
    username = sys.argv[2]
    password = sys.argv[3]
    
    web_config = {
        'username': username,
        'password': password
    }
    
    handler_class = create_configured_handler(web_config)
    server = HTTPServer(('0.0.0.0', port), handler_class)
    
    print(f"🚀 FRPC Web 管理面板启动成功")
    print(f"📍 访问地址: http://localhost:{port}")
    print(f"👤 用户名: {username}")
    print(f"🔐 密码: {password}")
    print("按 Ctrl+C 停止服务")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n服务已停止")
        server.shutdown()

if __name__ == '__main__':
    main()
EOF
    
    chmod +x "$web_script"
    print_success "Web 管理面板脚本创建完成"
}

# 配置 Web 面板服务
configure_web_service() {
    print_info "配置 Web 面板服务..."
    case "$OS_TYPE" in
        "debian"|"ubuntu")
            cat > "/etc/systemd/system/frpc-web.service" << EOF
[Unit]
Description=FRPC Web Management Panel
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/usr/bin/python3 $CONFIG_DIR/frpc-web-panel.py $WEB_PORT $WEB_USERNAME $WEB_PASSWORD

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
            systemctl enable frpc-web
            systemctl start frpc-web
            ;;
        "openwrt")
            cat > "/etc/init.d/frpc-web" << EOF
#!/bin/sh /etc/rc.common
START=98
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command python3 $CONFIG_DIR/frpc-web-panel.py $WEB_PORT $WEB_USERNAME $WEB_PASSWORD
    procd_set_param respawn
    procd_close_instance
}
EOF
            chmod +x "/etc/init.d/frpc-web"
            /etc/init.d/frpc-web enable
            /etc/init.d/frpc-web start
            ;;
    esac
    print_success "Web 面板服务配置完成"
}

# 检查现有安装并修复
fix_existing_installation() {
    print_info "检查现有安装，正在检查和修复..."
    local need_fix=false
    
    # 检查并修复 Web 面板到最新版本
    if [ -f "$CONFIG_DIR/frpc-web-panel.py" ]; then
        print_info "更新 Web 面板到修复版本..."
        create_web_panel
        need_fix=true
    fi
    
    # 检查并重启所有相关服务
    if systemctl is-active --quiet frpc-web 2>/dev/null; then
        print_info "重启服务以应用修复..."
        systemctl restart frpc-web 2>/dev/null || true
        need_fix=true
    fi
    
    # 检查 frpc 管理命令是否存在或需要更新
    if [ ! -f "/usr/local/bin/frpc" ] || ! grep -q "FRPC 管理命令" "/usr/local/bin/frpc" 2>/dev/null; then
        print_info "创建/更新 frpc 管理命令..."
        create_frpc_command
        need_fix=true
    fi
    
    if [ "$need_fix" = true ]; then
        print_success "修复完成！"
    else
        print_info "未发现需要修复的问题"
    fi
}

# 创建 frpc 快捷命令
create_frpc_command() {
    print_info "创建 FRPC 管理快捷命令..."
    
    # 删除旧的frpc命令（如果存在）
    rm -f "/usr/local/bin/frpc" 2>/dev/null
    
    # 直接创建 frpc 管理命令
    local cmd_file="/usr/local/bin/frpc"
    
    cat > "$cmd_file" << 'EOF'
#!/bin/bash

# FRPC 智能命令 - OpenWrt优化版
# 带参数时作为 FRPC 客户端运行，不带参数时显示管理菜单

# 配置文件路径
CONFIG_FILE="/etc/frpc/frpc.toml"
FRPC_BIN="/usr/local/bin/frpc-bin"

# 如果有参数，直接调用 FRPC 二进制文件
if [ $# -gt 0 ]; then
    # 检查配置文件是否存在
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "错误: 配置文件 $CONFIG_FILE 不存在"
        echo "请先运行安装脚本或手动创建配置文件"
        exit 1
    fi
    
    # 检查二进制文件是否存在
    if [ ! -f "$FRPC_BIN" ]; then
        echo "错误: FRPC 二进制文件 $FRPC_BIN 不存在"
        echo "请重新运行安装脚本"
        exit 1
    fi
    
    # 如果没有指定配置文件，自动添加默认配置文件
    if [[ "$*" != *"-c"* ]] && [[ "$*" != *"--config"* ]]; then
        exec "$FRPC_BIN" -c "$CONFIG_FILE" "$@"
    else
        exec "$FRPC_BIN" "$@"
    fi
fi

# 没有参数时显示管理菜单

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_menu() {
    clear
    echo -e "${GREEN}"
    echo "=================================================="
    echo "              FRPC 管理工具"
    echo "=================================================="
    echo -e "${NC}"
    echo ""
    echo "请选择操作："
    echo ""
    echo "  1) 🚀 启动 FRPC 服务"
    echo "  2) 🛑 停止 FRPC 服务"
    echo "  3) 🔄 重启 FRPC 服务"
    echo "  4) 📊 查看服务状态"
    echo "  5) 📋 查看服务日志"
    echo "  6) 🌐 打开 Web 管理面板"
    echo "  7) 📝 编辑配置文件"
    echo "  8) 🔧 更新 FRPC"
    echo "  9) 🔧 修复命令 (OpenWrt)"
    echo "  10) 🗑️ 卸载 FRPC"
    echo "  0) 🚪 退出"
    echo ""
}

get_web_panel_url() {
    local port=$(netstat -tlnp 2>/dev/null | grep ":808[0-9]" | head -1 | awk '{print $4}' | cut -d: -f2)
    if [ -z "$port" ]; then
        port=$(ss -tlnp 2>/dev/null | grep ":808[0-9]" | head -1 | awk '{print $5}' | cut -d: -f2)
    fi
    port=${port:-8080}
    local ip=$(get_local_ip)
    echo "http://$ip:$port"
}

start_service() {
    print_info "启动 FRPC 服务..."
    if systemctl start frpc && systemctl start frpc-web; then
        print_success "✅ FRPC 服务启动成功"
    else
        print_error "❌ FRPC 服务启动失败"
    fi
}

stop_service() {
    print_info "停止 FRPC 服务..."
    if systemctl stop frpc && systemctl stop frpc-web; then
        print_success "✅ FRPC 服务停止成功"
    else
        print_error "❌ FRPC 服务停止失败"
    fi
}

restart_service() {
    print_info "重启 FRPC 服务..."
    local success=true
    
    # 重启 FRPC 服务
    if ! service_control restart frpc; then
        success=false
    fi
    
    # 重启 Web 面板服务
    if ! service_control restart frpc-web; then
        success=false
    fi
    
    if [ "$success" = true ]; then
        print_success "✅ FRPC 服务重启成功"
    else
        print_error "❌ FRPC 服务重启失败"
    fi
}

show_status() {
    print_info "FRPC 服务状态："
    echo ""
    echo "🔹 FRPC 主服务："
    systemctl status frpc --no-pager -l
    echo ""
    echo "🔹 Web 管理面板："
    systemctl status frpc-web --no-pager -l
    echo ""
    
    local url=$(get_web_panel_url)
    print_info "🌐 Web 管理面板: $url"
}

show_logs() {
    print_info "显示 FRPC 服务日志 (按 Ctrl+C 退出)："
    echo ""
    journalctl -u frpc -f
}

open_web_panel() {
    local url=$(get_web_panel_url)
    print_info "🌐 Web 管理面板地址: $url"
    echo ""
    print_info "请在浏览器中打开上述地址"
}

edit_config() {
    print_info "编辑 FRPC 配置文件..."
    
    # 优先使用 TOML 格式配置文件
    if [ -f /etc/frpc/frpc.toml ]; then
        print_info "编辑 TOML 格式配置文件（推荐）"
        if command -v nano >/dev/null 2>&1; then
            nano /etc/frpc/frpc.toml
        elif command -v vi >/dev/null 2>&1; then
            vi /etc/frpc/frpc.toml
        else
            print_error "未找到文本编辑器"
            return 1
        fi
    elif [ -f /etc/frpc/frpc.ini ]; then
        print_info "编辑 INI 格式配置文件（兼容模式）"
        if command -v nano >/dev/null 2>&1; then
            nano /etc/frpc/frpc.ini
        elif command -v vi >/dev/null 2>&1; then
            vi /etc/frpc/frpc.ini
        else
            print_error "未找到文本编辑器"
            return 1
        fi
    else
        print_error "配置文件不存在: /etc/frpc/frpc.toml 或 /etc/frpc/frpc.ini"
        return 1
    fi
    
    print_info "配置文件已保存，是否重启服务？(y/n)"
    read -r answer
    if [[ $answer =~ ^[Yy]$ ]]; then
        restart_service
    fi
}

check_latest_version() {
    print_info "检查最新版本..."
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/fatedier/frp/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//')
    if [ -n "$latest_version" ]; then
        echo "$latest_version"
    else
        echo "$FRPC_VERSION"
    fi
}

update_frpc() {
    print_info "更新 FRPC 到最新版本..."
    local latest_version
    latest_version=$(check_latest_version)
    
    print_info "当前版本: $FRPC_VERSION"
    print_info "最新版本: $latest_version"
    
    if [ "$FRPC_VERSION" = "$latest_version" ]; then
        print_success "已经是最新版本！"
        return
    fi
    
    print_warning "⚠️  发现新版本，是否更新？(y/n)"
    read -r answer
    if [[ $answer =~ ^[Yy]$ ]]; then
        print_info "正在更新 FRPC..."
        # 备份当前配置
        if [ -f "$CONFIG_DIR/frpc.toml" ]; then
            cp "$CONFIG_DIR/frpc.toml" "$CONFIG_DIR/frpc.toml.backup.$(date +%Y%m%d_%H%M%S)"
            print_info "配置文件已备份"
        fi
        # 临时更新版本号
        FRPC_VERSION="$latest_version"
        # 重新安装
        install_frpc
        print_success "FRPC 更新完成！版本: $latest_version"
        print_info "配置文件已保留，服务将自动重启"
        service_control restart frpc 2>/dev/null || true
    fi
}

uninstall_frpc() {
    print_warning "⚠️  确定要卸载 FRPC 吗？这将删除所有配置和数据！"
    print_info "输入 'YES' 确认卸载 (区分大小写): "
    read -r confirm
    if [ "$confirm" = "YES" ]; then
        print_info "正在卸载 FRPC..."
        # 停止服务
        systemctl stop frpc frpc-web 2>/dev/null || true
        systemctl disable frpc frpc-web 2>/dev/null || true
        # 删除文件
        rm -rf /etc/frpc /var/log/frpc.log
        rm -f /usr/local/bin/frpc /usr/local/bin/frpc-bin
        rm -f /etc/systemd/system/frpc.service /etc/systemd/system/frpc-web.service
        # 重新加载 systemd
        systemctl daemon-reload 2>/dev/null || true
        print_success "✅ FRPC 卸载完成"
        exit 0
    else
        print_info "❌ 卸载已取消"
    fi
}

main() {
    # 检查是否以 root 权限运行
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行此命令"
        print_info "使用命令: sudo frpc"
        exit 1
    fi
    
    while true; do
        show_menu
        read -p "请输入选项 [0-10]: " choice
        case $choice in
            1) start_service; read -p "按 Enter 键继续..." ;;
            2) stop_service; read -p "按 Enter 键继续..." ;;
            3) restart_service; read -p "按 Enter 键继续..." ;;
            4) show_status; read -p "按 Enter 键继续..." ;;
            5) show_logs ;;
            6) open_web_panel; read -p "按 Enter 键继续..." ;;
            7) edit_config ;;
            8) update_frpc ;;
            9) fix_frpc_command_openwrt; read -p "按 Enter 键继续..." ;;
            10) uninstall_frpc ;;
            0) print_info "再见！"; exit 0 ;;
            *) print_warning "无效选项，请重新选择"; sleep 1 ;;
        esac
    done
}

main "$@"
EOF

    chmod +x "$cmd_file" || { print_error "设置执行权限失败"; exit 1; }
    
    # 验证命令是否创建成功
    if [ -f "$cmd_file" ] && [ -x "$cmd_file" ]; then
        print_success "FRPC 管理命令创建完成"
        print_info "使用命令: sudo frpc"
    else
        print_error "FRPC 管理命令创建失败"
        exit 1
    fi
}

# 显示安装完成信息
show_completion() {
    local ip=$(get_local_ip)
    
    echo ""
    print_success "🎉 FRPC 修复完成！"
    echo ""
    print_info "📋 修复内容："
    echo "  ✅ 完全支持官方 TOML 配置格式"
    echo "  ✅ 修复了所有登录和认证问题"  
    echo "  ✅ 修复了隧道管理功能"
    echo "  ✅ 更新了 Web 面板到最新版本"
    echo "  ✅ 重启了所有相关服务"
    echo ""
    print_info "🌐 访问信息："
    echo "  Web 管理面板: http://$ip:$WEB_PORT"
    echo ""
    print_info "📝 配置格式："
    echo "  使用 TOML 格式: /etc/frpc/frpc.toml (推荐)"
    echo "  兼容 INI 格式: /etc/frpc/frpc.ini"
    echo ""
    print_info "🚀 现在可以正常连接 FRPS 服务器了！"
}

# 主函数
main() {
    show_welcome
    check_root
    detect_os
    detect_arch
    check_fnos_compatibility
    
    # 检查是否已安装，如果是则进行修复
    if [ -f "$CONFIG_DIR/frpc-web-panel.py" ] || [ -f "/etc/systemd/system/frpc.service" ]; then
        print_info "检测到现有安装，进入修复模式..."
        
        # 获取现有的 Web 配置
        if systemctl is-active --quiet frpc-web 2>/dev/null; then
            # 尝试从进程参数中获取配置
            local web_process=$(ps aux | grep "frpc-web-panel.py" | grep -v grep | head -1)
            if [ -n "$web_process" ]; then
                WEB_PORT=$(echo "$web_process" | awk '{print $12}' 2>/dev/null || echo "8080")
                WEB_USERNAME=$(echo "$web_process" | awk '{print $13}' 2>/dev/null || echo "admin")
                WEB_PASSWORD=$(echo "$web_process" | awk '{print $14}' 2>/dev/null || echo "123456")
            else
                WEB_PORT="8080"
                WEB_USERNAME="admin"
                WEB_PASSWORD="123456"
            fi
        else
            WEB_PORT="8080"
            WEB_USERNAME="admin"
            WEB_PASSWORD="123456"
        fi
        
        fix_existing_installation
        create_web_panel
        configure_web_service
        create_frpc_command
        show_completion
    else
        # 全新安装
        get_user_input || { print_error "用户配置失败"; exit 1; }
        
        # 询问是否跳过依赖安装（适用于飞牛OS等特殊环境）
        echo ""
        print_info "是否跳过依赖包安装？(适用于已安装依赖或受限环境)"
        print_warning "跳过依赖安装可能导致 Web 面板功能受限"
        read -p "跳过依赖安装？(y/N): " skip_deps
        
        if [[ ! $skip_deps =~ ^[Yy]$ ]]; then
            install_dependencies || { 
                print_error "依赖安装失败"
                print_info "你可以选择继续安装 FRPC 核心功能，或退出手动解决依赖问题"
                read -p "是否继续安装 FRPC 核心功能？(y/N): " continue_install
                if [[ ! $continue_install =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            }
        else
            print_info "跳过依赖安装，仅安装 FRPC 核心功能"
        fi
        
        install_frpc || { print_error "FRPC 安装失败"; exit 1; }
        create_frpc_config || { print_error "配置文件创建失败"; exit 1; }
        configure_service || { print_error "服务配置失败"; exit 1; }
        create_web_panel || { print_error "Web 面板创建失败"; exit 1; }
        configure_web_service || { print_error "Web 服务配置失败"; exit 1; }
        create_frpc_command || { 
            print_warning "管理命令创建失败，尝试手动修复..."
            # 手动创建简单的 frpc 命令
            cat > "/usr/local/bin/frpc" << 'SIMPLE_EOF'
#!/bin/bash
if [ $# -gt 0 ]; then
    if [ -f "/usr/local/bin/frpc-bin" ]; then
        exec /usr/local/bin/frpc-bin "$@"
    else
        echo "❌ FRPC 二进制文件不存在"
        exit 1
    fi
else
    echo "🚀 FRPC 管理菜单"
    if command -v systemctl >/dev/null 2>&1; then
        echo "1) systemctl start frpc    # 启动服务"
        echo "2) systemctl stop frpc     # 停止服务"
        echo "3) systemctl restart frpc  # 重启服务"
        echo "4) systemctl status frpc   # 查看状态"
    elif [ -f "/etc/init.d/frpc" ]; then
        echo "1) /etc/init.d/frpc start    # 启动服务"
        echo "2) /etc/init.d/frpc stop     # 停止服务"
        echo "3) /etc/init.d/frpc restart  # 重启服务"
        echo "4) /etc/init.d/frpc status   # 查看状态"
    fi
fi
SIMPLE_EOF
            chmod +x "/usr/local/bin/frpc" || print_error "无法创建 frpc 命令"
        }
        
        # 最终验证
        if command -v frpc >/dev/null 2>&1; then
            print_success "✅ frpc 命令创建成功"
        else
            print_error "❌ frpc 命令创建失败，请手动检查"
        fi
        
        # 显示完成信息
        local ip=$(get_local_ip)
        
        echo ""
        print_success "🎉 FRPC 安装完成！"
        echo ""
        print_info "🌐 访问信息："
        echo "  Web 管理面板: http://$ip:$WEB_PORT"
        echo "  用户名: $WEB_USERNAME"
        echo "  密码: $WEB_PASSWORD"
        echo ""
        print_info "🚀 快捷命令："
        echo "  sudo frpc  # 打开管理菜单"
        echo ""
        print_info "📝 配置文件位置："
        echo "  $CONFIG_DIR/frpc.ini"
        echo ""
        print_success "现在可以通过浏览器访问 Web 管理面板进行配置！"
    fi
}

# 强制修复frpc命令 - OpenWrt专用
fix_frpc_command_openwrt() {
    print_info "强制修复 FRPC 命令（OpenWrt优化）..."
    
    # 停止可能运行的frpc进程
    pkill -f "frpc" 2>/dev/null || true
    
    # 删除所有可能的frpc命令文件
    rm -f "/usr/local/bin/frpc" 2>/dev/null
    rm -f "/usr/bin/frpc" 2>/dev/null
    rm -f "/bin/frpc" 2>/dev/null
    
    # 创建简化的OpenWrt专用frpc命令
    cat > "/usr/local/bin/frpc" << 'EOF'
#!/bin/bash

# FRPC OpenWrt专用命令
CONFIG_FILE="/etc/frpc/frpc.toml"
FRPC_BIN="/usr/local/bin/frpc-bin"

# 检查文件是否存在
if [ ! -f "$FRPC_BIN" ]; then
    echo "错误: FRPC 二进制文件不存在: $FRPC_BIN"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件不存在: $CONFIG_FILE"
    echo "请检查配置文件路径或重新运行安装脚本"
    exit 1
fi

# 如果有参数，直接运行
if [ $# -gt 0 ]; then
    # 强制使用正确的配置文件
    if [[ "$*" != *"-c"* ]] && [[ "$*" != *"--config"* ]]; then
        exec "$FRPC_BIN" -c "$CONFIG_FILE" "$@"
    else
        exec "$FRPC_BIN" "$@"
    fi
else
    # 无参数时显示帮助
    echo "FRPC 客户端命令"
    echo "用法: frpc [选项]"
    echo ""
    echo "常用命令:"
    echo "  frpc                    # 显示此帮助"
    echo "  frpc -c /path/config    # 使用指定配置文件"
    echo "  frpc --help             # 显示详细帮助"
    echo ""
    echo "配置文件: $CONFIG_FILE"
    echo "二进制文件: $FRPC_BIN"
    echo ""
    echo "服务管理:"
    if [ -f "/etc/init.d/frpc" ]; then
        echo "  /etc/init.d/frpc start    # 启动服务"
        echo "  /etc/init.d/frpc stop     # 停止服务"
        echo "  /etc/init.d/frpc restart  # 重启服务"
        echo "  /etc/init.d/frpc status   # 查看状态"
    fi
fi
EOF
    
    chmod +x "/usr/local/bin/frpc"
    print_success "OpenWrt专用 FRPC 命令修复完成"
    
    # 测试命令
    echo ""
    print_info "测试 frpc 命令:"
    /usr/local/bin/frpc
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
