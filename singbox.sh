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
# ==================== 智能获取最优 IP + 判断 v4/v6 + 地理位置 ====================
IP_V4=$(curl -s -4 --max-time 8 https://v4.ipmsb.com/ || curl -s -4 --max-time 8 https://v4.ident.me/ || echo "")
IP_V6=$(curl -s -6 --max-time 8 https://v6.ipmsb.com/ || curl -s -6 --max-time 8 https://v6.ident.me/ || echo "")

if [[ -n "$IP_V4" && "$IP_V4" != "" ]]; then
    SERVER_IP="$IP_V4"
    DISPLAY_IP="$IP_V4"
    IP_TO_GEO="$IP_V4"
    IP_TYPE="v4"
    echo "优先使用 IPv4：$IP_V4"
elif [[ -n "$IP_V6" && "$IP_V6" != "" ]]; then
    SERVER_IP="$IP_V6"
    DISPLAY_IP="[$IP_V6]"
    IP_TO_GEO="$IP_V6"
    IP_TYPE="v6"
    echo "使用 IPv6：$DISPLAY_IP"
else
    echo "警告：未能获取公网 IP！使用兜底方案"
    FALLBACK=$(curl -s https://ip.sb)
    SERVER_IP="$FALLBACK"
    [[ $FALLBACK == *":"* ]] && { DISPLAY_IP="[$FALLBACK]"; IP_TYPE="v6"; } || { DISPLAY_IP="$FALLBACK"; IP_TYPE="v4"; }
    IP_TO_GEO="$FALLBACK"
fi

# 自动识别地理位置
LOCATION=$(curl -s --max-time 10 "http://ip-api.com/json/$IP_TO_GEO?fields=status,countryCode,regionName,city")
if echo "$LOCATION" | grep -q '"status":"success"'; then
    COUNTRY_CODE=$(echo "$LOCATION" | grep -o '"countryCode":"[^"]*' | cut -d'"' -f4)
    REGION=$(echo "$LOCATION" | grep -o '"regionName":"[^"]*' | cut -d'"' -f4 | sed 's/ /-/g' | cut -c1-3 | tr '[:lower:]' '[:upper:]')

    if [[ "$COUNTRY_CODE" == "HK" || "$COUNTRY_CODE" == "SG" || "$COUNTRY_CODE" == "MO" ]]; then
        GEO_TAG="$COUNTRY_CODE"
    elif [[ "$COUNTRY_CODE" == "US" ]]; then
        GEO_TAG="USA-$REGION"
    elif [[ "$COUNTRY_CODE" == "CN" ]]; then
        GEO_TAG="CN-$REGION"
    else
        CITY=$(echo "$LOCATION" | grep -o '"city":"[^"]*' | cut -d'"' -f4 | cut -c1-3 | tr '[:lower:]' '[:upper:]')
        GEO_TAG="$COUNTRY_CODE-$CITY"
    fi
else
    GEO_TAG="Unknown"
fi

# 最终标签：v4-USA-CA   或   v6-HK
FINAL_TAG="${IP_TYPE}-${GEO_TAG}"

echo "节点标签自动生成：$FINAL_TAG"
echo "===================================================="

# ==================== 输出终极节点链接（带 v4/v6 + 地区标签）================
echo "终极双协议部署完成（2025 最强智能标签版）"
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
echo "Reality ShortId : $SHORT_ID"
echo "真实 IP（手动填用）: $SERVER_IP"
echo "===================================================="
