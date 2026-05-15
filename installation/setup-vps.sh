#!/bin/bash
# VPS First Setup — run this on the VPS via SCP then execute
# Usage:
#   1. scp scripts/vps-first-setup.sh ubuntu@43.129.38.221:~/
#   2. ssh ubuntu@43.129.38.221 "sudo bash ~/vps-first-setup.sh"
set -e

echo "=== VPS First Setup ==="

# ── Delete old users ──
echo "[1/6] Removing old vps users..."
for u in vps vps-deploy vps-agent deploy agent; do
    userdel -r "$u" 2>/dev/null && echo "  Removed $u" || true
done

# ── Create new users ──
echo "[2/6] Creating new users..."
useradd -m -d /home/deploy -s /bin/bash deploy
useradd -m -d /home/agent -s /bin/bash agent
groupadd -f production
usermod -aG production deploy
usermod -aG production ubuntu
mkdir -p /home/production/app
echo "  Created deploy, agent, production group"

# ── Install SSH keys ──
echo "[3/6] Installing SSH keys..."

mkdir -p /root/.ssh
cat > /root/.ssh/authorized_keys << 'KEYEOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIChdq00R9JMoCwVA/F3m0aLULklUKSts0jGPfuhXgbnu root@vps
KEYEOF
chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys
echo "  Root key installed"

mkdir -p /home/deploy/.ssh
cat > /home/deploy/.ssh/authorized_keys << 'KEYEOF'
command="/usr/local/bin/deploy-wrapper",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOGf/QqirWUP4fs1MVnM/VPgRHFyoMFQSUNSna2UyHO0 deploy@vps
KEYEOF
chmod 700 /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy
echo "  Deploy key installed"

mkdir -p /home/agent/.ssh
cat > /home/agent/.ssh/authorized_keys << 'KEYEOF'
command="/usr/local/bin/agent-wrapper",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHFgUUooeadnO49FvUE6FUOAlb9aPk7iP9KIiNbvKUAF agent@vps
KEYEOF
chmod 700 /home/agent/.ssh && chmod 600 /home/agent/.ssh/authorized_keys
chown -R agent:agent /home/agent
echo "  Agent key installed"

# ── Wrapper scripts ──
echo "[4/6] Installing wrapper scripts..."

cat > /usr/local/bin/deploy-wrapper << 'WRAPPER'
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
WRAPPER

cat > /usr/local/bin/agent-wrapper << 'WRAPPER'
#!/bin/bash
ALLOWED=(cat less more tail head ls find grep df du free uptime date ps top htop netstat ss ip ifconfig pwd echo printenv stat file uname hostname curl wget git systemctl journalctl)
CMD="$SSH_ORIGINAL_COMMAND"; [ -z "$CMD" ] && echo "Interactive shell denied." && exit 1
for a in "${ALLOWED[@]}"; do [ "${CMD%% *}" = "$a" ] && exec $CMD; done
echo "Command not allowed. Read-only access." && exit 1
WRAPPER

chmod +x /usr/local/bin/deploy-wrapper /usr/local/bin/agent-wrapper
echo "  Wrapper scripts installed"

# ── Security hardening ──
echo "[5/6] Security hardening..."
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sshd -t && systemctl restart sshd
echo "  SSH hardened (key-only)"

ufw --force reset 2>/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
echo "  UFW configured (22, 80, 443)"

# ── Install deps ──
echo "[6/6] Installing system dependencies..."
apt update -qq && apt install -y -qq git maven openjdk-17-jre-headless curl
echo "  Dependencies installed"

echo ""
echo "=== VPS Setup Complete ==="
echo "Test SSH: ssh vps-root 'echo OK'"
echo "Test deploy: ssh vps-deploy 'echo OK'"
echo "Test agent: ssh vps-agent 'echo OK'"
