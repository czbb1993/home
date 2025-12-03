#!/usr/bin/env bash
set -e

# ==================== 只需要改这里的两个地方 ====================
REALITY_DOMAIN="www.tesla.com"      # ← 改成你想要的伪装域名（必须是被墙但你能正常访问的大站）
PORT=443                            # ← 对外端口，建议保持 443
ENABLE_BBR=true                     # 是否开启 BBR（推荐 true）
# ================================================================

echo "===================================================="
echo " sing-box + Reality + Hysteria2 自动生成参数版"
echo " 域名和端口手动改，其他全部自动生成（更安全！）"
echo "===================================================="
# 安装 sing-box 预发布版（含 hysteria2）
bash -c (curl -fsSL https://sing-box.app/install.sh | sh)

# 创建目录 + 自签证书（10年，CN=bing.com）
mkdir -p /etc/hysteria /etc/sing-box
openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
openssl req -new -x509 -days 3650 -key /etc/hysteria/private.key -out /etc/hysteria/cert.pem -subj "/CN=bing.com"


# 1. 自动生成 UUID
FIXED_UUID=$(sing-box generate uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID: $FIXED_UUID"

# 2. 自动生成 Hysteria2 强密码（16位）
HY2_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
echo "Hysteria2 密码: $HY2_PASSWORD"

# 3. 自动生成 Reality 密钥对
echo "正在生成 Reality 密钥对..."
KEYPAIR=$(sing-box generate reality-keypair 2>/dev/null || curl -fsSL https://raw.githubusercontent.com/SagerNet/sing-box/main/install.sh | bash -s -- generate reality-keypair)
REALITY_PRIVATE_KEY=$(echo "$KEYPAIR" | grep PrivateKey | awk '{print $2}')
REALITY_PUBLIC_KEY=$(echo "$KEYPAIR"  | grep PublicKey  | awk '{print $2}')
echo "Reality PublicKey: $REALITY_PUBLIC_KEY"

# 4. 自动生成两个 8 位 shortId（兼容性最好）
SHORT_ID1=$(sing-box generate rand --hex 4 | tr -d '\n')
SHORT_ID2=$(sing-box generate rand --hex 4 | tr -d '\n')
SHORT_IDS="$SHORT_ID1,$SHORT_ID2"
echo "ShortId: $SHORT_ID1 和 $SHORT_ID2"


# 写入配置（所有参数自动填充）
cat > /etc/sing-box/config.json <<EOF
"inbounds": [
  {
    "type": "hysteria2",
    "tag": "hy2",
    "listen": "::",
    "listen_port": 443,
    "up_mbps": 100,
    "down_mbps": 200,
    "password": "$HY2_PASSWORD",
    "tls": {
      "enabled": true,
      "server_name": "bing.com",
      "certificate_path": "/etc/hysteria/cert.pem",
      "key_path": "/etc/hysteria/private.key"
    },
    "sniff": true,
    "sniff_override_fields": true
  },
  {
    "type": "vless",
    "tag": "vless-reality",
    "listen": "::",
    "listen_port": 443,
    "sniff": true,
    "sniff_override_fields": true,
    "users": [
      { "uuid": "$FIXED_UUID", "flow": "xtls-rprx-vision" }
    ],
    "tls": {
      "enabled": true,
      "server_name": "$REALITY_DOMAIN",
      "reality": {
        "enabled": true,
        "handshake": { "server": "$REALITY_DOMAIN", "server_port": 443 },
        "private_key": "$REALITY_PRIVATE_KEY",
        "public_key": "$REALITY_PUBLIC_KEY",
        "short_id": [ "$SHORT_ID1", "$SHORT_ID2" ]
      },
      "fallback": {
        "dest": "www.tesla.com:443",
        "xver": 0
      },
      "server_name": ["$REALITY_DOMAIN"]
    },
    "multiplex": { "enabled": false }
  }
]
EOF

# 启动服务
systemctl restart sing-box
systemctl enable sing-box &>/dev/null || true

# 开启 BBR（可选）
if [ "$ENABLE_BBR" = true ]; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null
fi

# 获取公网 IP 并输出完整信息
IP=$(curl -s4 ip.sb || curl -s6 ip.sb)

echo "===================================================="
echo "部署完成！以下为本次生成的专属节点信息（已复制到剪贴板可直接粘贴）"
echo ""
echo "【Hysteria2】"
echo "地址: $IP"
echo "端口: $PORT"
echo "密码: $HY2_PASSWORD"
echo "SNI: bing.com（客户端允许不安全/跳过证书验证）"
echo "链接: hysteria2://$HY2_PASSWORD@$IP:$PORT/?sni=bing.com&insecure=1#Hy2-$IP"
echo ""
echo "【VLESS + Reality + Vision】"
echo "地址: $IP"
echo "端口: $PORT"
echo "UUID: $FIXED_UUID"
echo "Flow: xtls-rprx-vision"
echo "加密: none"
echo "TLS: reality"
echo "SNI: $REALITY_DOMAIN"
echo "PublicKey: $REALITY_PUBLIC_KEY"
echo "ShortId: $SHORT_ID1 或 $SHORT_ID2（都可用）"
echo "完整链接:"
echo "vless://$FIXED_UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$REALITY_DOMAIN&fp=chrome&pbk=$REALITY_PUBLIC_KEY&sid=$SHORT_ID1&type=tcp#Reality-$IP"
echo ""
echo "查看状态: systemctl status sing-box"
echo "实时日志: journalctl -u sing-box -f"
echo "===================================================="

# 自动复制两条链接到剪贴板（如果你装了 clip 工具的话，常见于大多数面板）
if command -v xclip >/dev/null; then
    echo -e "hysteria2://$HY2_PASSWORD@$IP:$PORT/?sni=bing.com&insecure=1#Hy2-$IP\nvless://$FIXED_UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$REALITY_DOMAIN&fp=chrome&pbk=$REALITY_PUBLIC_KEY&sid=$SHORT_ID1&type=tcp#Reality-$IP" | xclip -sel clip
    echo "两条链接已复制到剪贴板，直接粘贴到客户端即可！"
fi
