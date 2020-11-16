#!/usr/bin/env bash

set -euxo pipefail

# Install WireGuard
apt update
apt -y install wireguard

# Enable IP forwarding
sed -i '/^#net.ipv4.ip_forward=1/s/^#//' /etc/sysctl.conf
sysctl -p

# Firewall
apt -y install ufw
ufw allow ssh
ufw allow 51820/udp
systemctl enable ufw

# Copy generated config
mv /tmp/wg0.conf /etc/wireguard/

# Enable & startup at boot
wg-quick up wg0
systemctl enable wg-quick@wg0
modprobe wireguard
