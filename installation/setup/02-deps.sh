#!/bin/bash
# STEP 2: Install Dependencies
# Run: sudo bash 02-deps.sh
set -e

echo "=== Installing system dependencies ==="
apt update -qq
apt install -y -qq git maven openjdk-17-jre-headless curl

echo "✅ STEP 2 COMPLETE — Dependencies installed"
echo "Run: bash 03-clone-repos.sh"
