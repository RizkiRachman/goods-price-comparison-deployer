#!/bin/bash
# STEP 4: Systemd Service
# Run: sudo bash 04-systemd.sh
set -e

echo "=== Creating systemd service ==="

cat > /etc/systemd/system/goods-price-service.service << 'EOF'
[Unit]
Description=Goods Price Comparison Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=deploy
Group=production
WorkingDirectory=/home/production/app/goods-price-comparison-service
ExecStart=/usr/bin/java -jar /home/production/app/goods-price-comparison-service/target/goods-price-comparison-service-1.0.0-SNAPSHOT.jar
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
EnvironmentFile=/home/production/app/goods-price-comparison-service/.env.production

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable goods-price-service

echo ""
echo "✅ STEP 4 COMPLETE — Service created but not started"
echo "Next: Create .env.production file, then run: bash 05-deploy.sh"
