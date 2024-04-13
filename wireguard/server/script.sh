#!/usr/bin/env bash

set -euxo pipefail

# Make upgrades non interactive, to avoid prompts like this:
#
#  A new version (/tmp/tmp.7xIRMaLcC1) of configuration file /etc/ssh/sshd_config
#  is available%!(PACKER_COMMA) but the version installed currently has been locally modified.
#
#    1. install the package maintainer's version
#    2. keep the local version currently installed
#    3. show the differences between the versions
#    4. show a side-by-side difference between the versions
#    5. show a 3-way difference between available versions
#    6. do a 3-way merge between available versions
#    7. start a new shell to examine the situation
#
export DEBIAN_FRONTEND=noninteractive

# Install WireGuard
apt update
apt -yq upgrade
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
