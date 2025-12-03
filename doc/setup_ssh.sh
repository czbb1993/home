#!/bin/bash
set -euo pipefail

# ======== 请在这里修改成你的公钥 ========
# 可以放一个，也可以放多个，每行一个
AUTHORIZED_KEYS=$(cat <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHxwLCUSWna7aK5IrabBLxnOAX9b2w4bHHBpbb6mgurm czbb
EOF
)
# ===========================================

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/root/ssh_backup_$(date +%Y%m%d_%H%M%S)"
NEW_PORT=8023

echo "=== 开始配置 SSH（端口 $NEW_PORT，只允许密钥登录） ==="

# 1. 备份原有配置
mkdir -p "$BACKUP_DIR"
cp "$SSHD_CONFIG" "$BACKUP_DIR/"
[ -f /etc/ssh/sshd_config.d/00-custom.conf ] && cp /etc/ssh/sshd_config.d/00-custom.conf "$BACKUP_DIR/" || true

# 2. 修改端口
sed -i "s/^#Port 22/Port $NEW_PORT/g" "$SSHD_CONFIG"
sed -i "s/^Port .*/Port $NEW_PORT/g" "$SSHD_CONFIG"
if ! grep -q "^Port $NEW_PORT" "$SSHD_CONFIG"; then
    echo "Port $NEW_PORT" >> "$SSHD_CONFIG"
fi

# 3. 强制只允许密钥登录，关闭密码登录
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/g' "$SSHD_CONFIG"
sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/g' "$SSHD_CONFIG"
sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/g' "$SSHD_CONFIG"
sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/g' "$SSHD_CONFIG"

# 常见发行版额外关闭的地方
sed -i 's/^#ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/g' "$SSHD_CONFIG"
sed -i 's/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/g' "$SSHD_CONFIG"

# 4. 写入你的公钥（覆盖或追加）
mkdir -p /root/.ssh
chmod 700 /root/.ssh

echo "$AUTHORIZED_KEYS" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# 如果你还有其他普通用户需要登录，也一并写进去（示例用户 admin）
# mkdir -p /home/admin/.ssh
# echo "$AUTHORIZED_KEYS" > /home/admin/.ssh/authorized_keys
# chown -R admin:admin /home/admin/.ssh
# chmod 700 /home/admin/.ssh
# chmod 600 /home/admin/.ssh/authorized_keys

# 5. 额外安全加固（推荐）
echo "PermitRootLogin prohibit-password" >> "$SSHD_CONFIG"   # root 只允许密钥
echo "PermitEmptyPasswords no" >> "$SSHD_CONFIG"
echo "ClientAliveInterval 300" >> "$SSHD_CONFIG"
echo "ClientAliveCountMax 0" >> "$SSHD_CONFIG"

# 6. 检查配置语法
sshd -t && echo "sshd 配置语法检查通过"

# 7. 重启 sshd（根据不同发行版）
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd || systemctl restart ssh
elif command -v service >/dev/null 2>&1; then
    service sshd restart || service ssh restart
else
    /etc/init.d/ssh restart || /etc/init.d/sshd restart
fi

echo "=== SSH 配置完成！==="
echo "新端口：$NEW_PORT"
echo "密码登录已禁用，只允许密钥登录"
echo "备份保存在：$BACKUP_DIR"
echo "请用下面命令测试新端口是否生效（在新窗口操作，防止把自己锁外面）："
echo "ssh -p $NEW_PORT root@$(hostname -I | awk '{print $1}')"
