#!/usr/bin/env bash

# 安装 sing-box beta 版（官方最新脚本，含 Hysteria2）
#bash -c "$(curl -L sing-box.vercel.app)" @ install

if ! systemctl is-enabled sing-box &>/dev/null; then
    systemctl enable sing-box
    systemctl start sing-box
    echo "sing-box 已设置为开机自启"
else
    echo "sing-box 已经开机自启，无需重复设置"
fi

# 创建目录 + 自签证书（10年，CN=bing.com）
# mkdir -p /etc/hysteria /etc/sing-box
# openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
# openssl req -new -x509 -days 3650 -key /etc/hysteria/private.key -out /etc/hysteria/cert.pem -subj "/CN=bing.com"

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
echo "正在检测公网 IP（优先 IPv4）..."
IP_V4=$(curl -s -4 --max-time 8 https://v4.ipmsb.com/ || curl -s -4 --max-time 8 https://v4.ident.me/ || echo "")
IP_V6=$(curl -s -6 --max-time 8 https://v6.ipmsb.com/ || curl -s -6 --max-time 8 https://v6.ident.me/ || echo "")

if [[ -n "$IP_V4" && "$IP_V4" != " " ]]; then
    SERVER_IP="$IP_V4"; DISPLAY_IP="$IP_V4"; IP_TO_GEO="$IP_V4"; IP_TYPE="v4"
    echo "优先使用 IPv4：$IP_V4"
elif [[ -n "$IP_V6" && "$IP_V6" != " " ]]; then
    SERVER_IP="$IP_V6"; DISPLAY_IP="[$IP_V6]"; IP_TO_GEO="$IP_V6"; IP_TYPE="v6"
    echo "使用 IPv6：$DISPLAY_IP"
else
    FALLBACK=$(curl -s --max-time 10 https://api.ip.sb/ip || curl -s --max-time 10 https://ifconfig.co/ip || echo "127.0.0.1")
    SERVER_IP="$FALLBACK"; IP_TO_GEO="$FALLBACK"
    [[ $FALLBACK == *":"* ]] && { DISPLAY_IP="[$FALLBACK]"; IP_TYPE="v6"; } || { DISPLAY_IP="$FALLBACK"; IP_TYPE="v4"; }
    echo "兜底 IP：$DISPLAY_IP"
fi

GEO_TAG=""

{
    # 优先 ip-api.com，兜底 ip.sb（4 秒总超时）
    DATA=$(curl -s --max-time 4 "https://ip-api.com/json/$IP_TO_GEO?fields=countryCode,regionName" 2>/dev/null || \
           curl -s --max-time 4 "https://api.ip.sb/geoip/$IP_TO_GEO" 2>/dev/null || echo "")

    # ========== 用 awk 超级稳健提取 CC（兼容两种 API） ==========
    CC=$(echo "$DATA" | awk -F'"' '/countryCode":/ {for(i=1;i<=NF;i++) if($i ~ /^[A-Z]{2}$/) {print $i; exit}} /country_code":/ {for(i=1;i<=NF;i++) if($i ~ /^[A-Z]{2}$/) {print $i; exit}}' | head -1)

    # ========== 用 awk 提取 REGION（取前 8 字符，大写，去空格） ==========
    REGION=$(echo "$DATA" | awk -F'"' '/regionName":/ || /region":/ {for(i=1;i<=NF;i++) if($i ~ /^[a-zA-Z ]+$/) {gsub(/ /,"",$i); print toupper(substr($i,1,8)); exit}}' | head -1)

    # ========== 生成 GEO_TAG（如果 CC 有效） ==========
    if [[ -n "$CC" && ${#CC} -eq 2 && "$CC" != "XX" && "$CC" != "ZZ" ]]; then
        case "$CC" in
            HK|SG|MO|TW|JP|KR|KP) GEO_TAG="$CC" ;;  # 亚洲热门只用国家码
            US) GEO_TAG="USA${REGION:+-${REGION}}" ;;
            CN) GEO_TAG="CN${REGION:+-${REGION}}" ;;
            *) GEO_TAG="${CC}${REGION:+-${REGION}}" ;;  # 其他国家 + 地区
        esac
        echo "调试：CC=$CC, REGION=$REGION, GEO_TAG=$GEO_TAG"  # 临时调试行，成功后可删
    else
        echo "调试：CC 提取失败（DATA: $DATA）"  # 临时调试，查看 DATA 是否为空
    fi
} &

sleep 4.5
wait $! 2>/dev/null || true
FINAL_TAG="${GEO_TAG}${GEO_TAG:+-}${IP_TYPE}"

# ==================== 输出终极节点链接（带 v4/v6 + 地区标签）================
echo "服务器地址：$DISPLAY_IP   |   标签：$FINAL_TAG"
echo ""
echo "Hysteria2（主力冲量）"
echo "hy2://$HY2_PASSWORD@$DISPLAY_IP:$PORT_HY2/?sni=bing.com&insecure=1&alpn=h3#Hy2-$FINAL_TAG-Home"
echo ""
echo "VLESS + Reality（永不封神器）"
echo "vless://$FIXED_UUID@$DISPLAY_IP:$PORT_REALITY?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$REALITY_DOMAIN&fp=chrome&pbk=$REALITY_PUBLIC_KEY&sid=0123456789abcdef&type=tcp&packetEncoding=true#Reality-$FINAL_TAG-Home"
echo ""
echo "【参数备份】"
echo "Hy2 密码       : $HY2_PASSWORD"
echo "UUID           : $FIXED_UUID"
echo "Reality 公钥    : $REALITY_PUBLIC_KEY"
echo "真实 IP（手动填用）: $SERVER_IP"
echo "===================================================="
