#!/usr/bin/env bash
set -e

# ==================== 只需要改这里的两个地方 ====================
REALITY_DOMAIN="www.tesla.com"  # 建议这个，比 tesla 更不易被针对
PORT=443
ENABLE_BBR=true
# ================================================================

echo "===================================================="
echo " sing-box + Reality + Hysteria2 自动生成参数版 (2025-12 优化)"
echo " 域名和端口手动改，其他全部自动生成（更安全！）"
echo "===================================================="

# 安装 sing-box beta 版（官方最新脚本，含 Hysteria2）
bash -c "$(curl -L sing-box.vercel.app)" @ install

# 创建目录 + 自签证书（10年，CN=bing.com）
mkdir -p /etc/hysteria /etc/sing-box
openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
openssl req -new -x509 -days 3650 -key /etc/hysteria/private.key -out /etc/hysteria/cert.pem -subj "/CN=bing.com"

# 1. 自动生成 UUID
FIXED_UUID=$(sing-box generate uuid)
echo "生成的 UUID: $FIXED_UUID"

# 2. 自动生成 Hysteria2 强密码（16位）
HY2_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
echo "Hysteria2 密码: $HY2_PASSWORD"

# 3. 自动生成 Reality 密钥对
echo "正在生成 Reality 密钥对..."
KEYPAIR=$(sing-box generate reality-keypair)
REALITY_PRIVATE_KEY=$(echo "$KEYPAIR" | grep PrivateKey | awk '{print $2}')
REALITY_PUBLIC_KEY=$(echo "$KEYPAIR" | grep PublicKey | awk '{print $2}')
echo "Reality PublicKey: $REALITY_PUBLIC_KEY"

# 4. 自动生成两个 8 位 shortId（兼容性最好）
SHORT_ID1=$(sing-box generate rand --hex 4 | tr -d '\n')
SHORT_ID2=$(sing-box generate rand --hex 4 | tr -d '\n')
echo "ShortId: $SHORT_ID1 和 $SHORT_ID2"

# 写入完整配置（log + inbounds + outbounds，443 共存 + sniff + fallback）
cat > /etc/sing-box/config.json <<EOF
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-443",
      "listen": "::",
      "listen_port": 443,
      "sniff": true,
      "sniff_override_fields": true
    },
    {
      "type": "hysteria2",
      "tag": "hy2",
      "listen": "127.0.0.1",
      "listen_port": 3000,
      "up_mbps": 300,
      "down_mbps": 800,
      "password": "$HY2_PASSWORD",
      "obfs": {
        "type": "salamander",
        "password": "$HY2_PASSWORD"
      },
      "masquerade": "https://bing.com",
      "tls": {
        "enabled": true,
        "server_name": "bing.com",
        "certificate_path": "/etc/hysteria/cert.pem",
        "key_path": "/etc/hysteria/private.key"
      }
    },
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "127.0.0.1",
      "listen_port": 3001,
      "users": [{"uuid": "$FIXED_UUID", "flow": "xtls-rprx-vision"}],
      "tls": {
        "enabled": true,
        "server_name": "$REALITY_DOMAIN",
        "reality": {
          "enabled": true,
          "handshake": {"server": "$REALITY_DOMAIN", "server_port": 443},
          "private_key": "$REALITY_PRIVATE_KEY",
          "public_key": "$REALITY_PUBLIC_KEY",
          "short_id": ["$SHORT_ID1", "$SHORT_ID2"]
        },
        "server_names": ["$REALITY_DOMAIN", "www.microsoft.com", "bing.com"]
      },
      "transport": {
        "type": "http",
        "path": "/reality-handshake"
      },
      "multiplex": {"enabled": false}
    }
  ],
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ],
  "route": {
    "rules": [
      {"inbound": "mixed-443", "port": 3000, "outbound": "hy2"},
      {"inbound": "mixed-443", "protocol": "tls", "outbound": "vless-reality"},
      {"inbound": "mixed-443", "outbound": "direct"}
    ]
  }
}
EOF

# 启动服务
systemctl restart sing-box
systemctl enable sing-box &>/dev/null || true

# 开启 BBR（可选，避免重复）
if [ "$ENABLE_BBR" = true ]; then
    if ! grep -q "net.core.default_qdisc" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi
    if ! grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    sysctl -p >/dev/null
fi

# 获取公网 IP 并输出完整信息
IP=$(curl -s4 ip.sb || curl -s6 ip.sb || curl -s ipinfo.io/ip)
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
