#!/bin/bash
# STEP 3: Clone Repos & Maven Auth
# Run: sudo bash 03-clone-repos.sh
set -e

echo "=== [1/2] Cloning repositories ==="
cd /home/production/app
git clone https://github.com/RizkiRachman/goods-price-comparison-service.git
git clone https://github.com/RizkiRachman/goods-price-comparison-dashboard.git
chown -R :production /home/production/app/*
chmod -R g+w /home/production/app/*
git config --global safe.directory "*"

echo "=== [2/2] Maven settings for GitHub Packages ==="
mkdir -p /home/deploy/.m2
cat > /home/deploy/.m2/settings.xml << 'EOF'
<settings>
  <servers>
    <server>
      <id>github</id>
      <username>rizkirachman</username>
      <password>ghp_your_token_here</password>
    </server>
  </servers>
</settings>
EOF
chmod 600 /home/deploy/.m2/settings.xml
chown -R deploy:deploy /home/deploy/.m2

echo ""
echo "✅ STEP 3 COMPLETE"
echo "⚠️  Update the GitHub token in /home/deploy/.m2/settings.xml"
echo "Then run: bash 04-systemd.sh"
