#!/bin/bash
# STEP 1: VPS User & Key Setup
# Run: sudo bash 01-users.sh
set -e

echo "=== [1/5] Removing old users ==="
for u in vps vps-deploy vps-agent deploy agent; do
    userdel -r "$u" 2>/dev/null && echo "  Removed $u" || true
done

echo "=== [2/5] Creating new users ==="
useradd -m -d /home/deploy -s /bin/bash deploy
useradd -m -d /home/agent -s /bin/bash agent
groupadd -f production
usermod -aG production deploy
usermod -aG production ubuntu
mkdir -p /home/production/app
echo "  Users created"

echo "=== [3/5] Installing SSH keys ==="
mkdir -p /root/.ssh
cat > /root/.ssh/authorized_keys << 'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEQu3E0ZayvOCm98UA262mRr1jAjOqiFwwvF4S9fqraX root@vps
EOF
chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys

mkdir -p /home/deploy/.ssh
cat > /home/deploy/.ssh/authorized_keys << 'EOF'
command="/usr/local/bin/deploy-wrapper",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDbwXs60hW9WVkYKVIUdhqn1jMAPwu7ALTbdyE3E5Y9e deploy@vps
EOF
chmod 700 /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy

mkdir -p /home/agent/.ssh
cat > /home/agent/.ssh/authorized_keys << 'EOF'
command="/usr/local/bin/agent-wrapper",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIELiV9SgACpzzNEHoDvYzOblf9XmXrbH2wEeeQqq3oI9 agent@vps
EOF
chmod 700 /home/agent/.ssh && chmod 600 /home/agent/.ssh/authorized_keys
chown -R agent:agent /home/agent
echo "  SSH keys installed"

echo "=== [4/5] Installing wrapper scripts ==="
cat > /usr/local/bin/deploy-wrapper << 'W'
#!/bin/bash
RESTRICTED_DIR="/home/production/app"
ALLOWED_PREFIXES=("/home/production/app/goods-price-comparison-service" "/home/production/app/goods-price-comparison-dashboard")
is_path_allowed() { local p="$1"; for x in "${ALLOWED_PREFIXES[@]}"; do [[ "$p" == "$x"* ]] && return 0; done; return 1; }
CMD="$SSH_ORIGINAL_COMMAND"; [ -z "$CMD" ] && echo "Interactive shell denied." && exit 1
if [[ "$CMD" == cd\ * ]]; then CD_DIR=$(echo "$CMD" | sed -n "s/^cd \([^ ]*\).*/\1/p")
  if [ -n "$CD_DIR" ] && is_path_allowed "$CD_DIR"; then REAL_CMD=$(echo "$CMD" | sed "s/^cd [^ ]* && //")
    [ -n "$REAL_CMD" ] && CMD="$REAL_CMD" && cd "$CD_DIR"; fi; fi
case "${CMD%% *}" in ls|cat|tail|head|less|more|grep|find|echo|test|\[) exec $CMD;; esac
[ "${CMD%% *}" = "git" ] && exec $CMD
for a in rsync scp cp mv rm mkdir touch; do [ "${CMD%% *}" = "$a" ] && exec $CMD; done
exec $CMD
W
chmod +x /usr/local/bin/deploy-wrapper

cat > /usr/local/bin/agent-wrapper << 'W'
#!/bin/bash
ALLOWED=(cat less more tail head ls find grep df du free uptime date ps top htop netstat ss ip ifconfig pwd echo printenv stat file uname hostname curl wget git systemctl journalctl)
CMD="$SSH_ORIGINAL_COMMAND"; [ -z "$CMD" ] && echo "Interactive shell denied." && exit 1
for a in "${ALLOWED[@]}"; do [ "${CMD%% *}" = "$a" ] && exec $CMD; done
echo "Command not allowed. Read-only access." && exit 1
W
chmod +x /usr/local/bin/agent-wrapper
echo "  Wrapper scripts installed"

echo "=== [5/5] Security hardening ==="
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sshd -t && systemctl restart sshd
ufw --force reset && ufw default deny incoming && ufw default allow outgoing
ufw allow ssh && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable
echo "  SSH hardened, UFW configured"

echo ""
echo "✅ STEP 1 COMPLETE"
echo "Run: bash 02-deps.sh"
