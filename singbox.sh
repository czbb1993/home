#!/usr/bin/env bash
set -e

# 安装 sing-box beta 版（官方最新脚本，含 Hysteria2）
#bash -c "$(curl -L sing-box.vercel.app)" @ install

systemctl enable sing-box
systemctl start sing-box

# 创建目录 + 自签证书（10年，CN=bing.com）
mkdir -p /etc/hysteria /etc/sing-box
openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
openssl req -new -x509 -days 3650 -key /etc/hysteria/private.key -out /etc/hysteria/cert.pem -subj "/CN=bing.com"

# 1. 先把变量读进来（防止脚本里没定义）
source /dev/null  # 清空
REALITY_DOMAIN="www.microsoft.com"
PORT_HY2=443
PORT_REALITY=8443

# 2. 生成/读取密钥（如果已经有就直接用）
[ -f /etc/hysteria/private.key ] || openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
[ -f /etc/hysteria/cert.pem ] || openssl req -new -x509 -days 3650 -key /etc/hysteria/private.key -out /etc/hysteria/cert.pem -subj "/CN=bing.com"
[ -z "$HY2_PASSWORD" ] && HY2_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
[ -z "$FIXED_UUID" ] && FIXED_UUID=$(sing-box generate uuid)
[ -z "$KEYPAIR" ] && KEYPAIR=$(sing-box generate reality-keypair)
REALITY_PRIVATE_KEY=$(echo "$KEYPAIR" | grep PrivateKey | awk '{print $2}')
REALITY_PUBLIC_KEY=$(echo "$KEYPAIR" | grep PublicKey | awk '{print $2}')

# 3. 写入终极双端口配置（2025 年最稳写法）
cat > /etc/sing-box/config.json <<EOF
{
  "inbounds": [
    {
      "type": "hysteria2",
      "listen": "::",
      "listen_port": $PORT_HY2,
      "users": [
                {
                    "password": "$HY2_PASSWORD", //你的密码
                }
            ],
      "masquerade": "https://bing.com",
      "tls": {
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "/etc/hysteria/cert.pem",
                "key_path": "/etc/hysteria/private.key"
            }
        },
    {
      "type": "vless",
      "listen": "::",
      "listen_port": $PORT_REALITY,
      "users": [{"uuid": "$FIXED_UUID", "flow": "xtls-rprx-vision"}],
      "tls": {
                "enabled": true,
                    "server_name": "$REALITY_DOMAIN",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "$REALITY_DOMAIN",
                        "server_port": 443
                    },
                    "private_key": "$REALITY_PRIVATE_KEY", //vps上执行sing-box generate reality-keypair
                    "short_id": [
                        "0123456789abcdef"// 0到f，长度为2的倍数，长度上限为16，默认这个也可以
                    ]
                }
            }
        }
    ],
  "outbounds": [
        {
            "type": "direct"
        }
    ]
}
EOF

# 4. 重启
systemctl restart sing-box

# 5. 输出新节点信息
# ==================== 智能获取最优 IP（优先 IPv4 → 再 IPv6）====================
# 方法：同时请求多个常用 IP 查询服务，谁先返回 IPv4 就用谁；都超时就用 IPv6
IP_V4=$(curl -s -4 --max-time 8 https://v4.ipmsb.com/ || curl -s -4 --max-time 8 https://v4.ident.me/ || echo "")
IP_V6=$(curl -s -6 --max-time 8 https://v6.ipmsb.com/ || curl -s -6 --max-time 8 https://v6.ident.me/ || echo "")

if [[ -n "$IP_V4" && "$IP_V4" !=, ]]; then
    SERVER_IP="$IP_V4"
    DISPLAY_IP="$IP_V4"
    echo "检测到 IPv4 可用，优先使用：$IP_V4"
elif [[ -n "$IP_V6" && "$IP_V6" != *":"* ]]; then
    SERVER_IP="$IP_V6"
    DISPLAY_IP="[$IP_V6]"   # IPv6 必须加方括号
    echo "仅检测到 IPv6，使用：$DISPLAY_IP"
else
    echo "警告：未能获取公网 IP！将尝试使用 ip.sb 兜底（可能不准）"
    FALLBACK=$(curl -s https://ip.sb)
    SERVER_IP="$FALLBACK"
    [[ $FALLBACK == *":"* ]] && DISPLAY_IP="[$FALLBACK]" || DISPLAY_IP="$FALLBACK"
fi

# ==================== 输出节点信息（已完美兼容 IPv4/IPv6/双栈）====================
echo "===================================================="
echo "终极双协议一键部署完成（2025 最强双栈兼容版）"
echo "服务器最优地址：$DISPLAY_IP   (原始IP：$SERVER_IP)"
echo ""
echo "Hysteria2（主力冲量，443端口）"
echo "hysteria2://$HY2_PASSWORD@$DISPLAY_IP:$PORT_HY2/?sni=bing.com&insecure=1&alpn=h3#Hy2-Main-443"
echo ""
echo "VLESS + Reality（永不封，8443端口）"
echo "vless://$FIXED_UUID@$DISPLAY_IP:$PORT_REALITY?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$REALITY_DOMAIN&fp=chrome&pbk=$REALITY_PUBLIC_KEY&sid=0123456789abcdef&type=tcp&packetEncoding=true#Reality-Backup-8443"
echo ""
echo "【关键参数备份】"
echo "Hy2 密码      : $HY2_PASSWORD"
echo "UUID          : $FIXED_UUID"
echo "Reality 公钥   : $REALITY_PUBLIC_KEY"
echo "Reality ShortId: $SHORT_ID"
echo "===================================================="

