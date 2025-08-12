#!/bin/bash

# This script uninstalls WireGuard and reverts the changes made by the setup script.
# It should be run with root privileges.

# --- Exit on error ---
set -e

# --- Check for root privileges ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

echo "==== Starting WireGuard Uninstallation ===="

# --- 1. Stop and Disable WireGuard Service ---
echo "--> Stopping and disabling WireGuard service..."
if systemctl is-active --quiet wg-quick@wg0; then
    systemctl stop wg-quick@wg0
fi
if systemctl is-enabled --quiet wg-quick@wg0; then
    systemctl disable wg-quick@wg0
fi

# --- 2. Firewall Configuration ---
echo "--> Removing firewall rules..."
ufw delete allow 51820/udp

# --- 3. Revert Network Configuration ---
echo "--> Reverting IP forwarding..."
# Remove the line if it exists
sed -i '/net.ipv4.ip_forward=1/d' /etc/sysctl.conf
sysctl -p

echo "--> Reverting UFW forward policy..."
# Set the forward policy back to DROP
sed -i 's/DEFAULT_FORWARD_POLICY="ACCEPT"/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw
# Reload ufw to apply changes
ufw reload

# --- 4. Remove WireGuard Configuration ---
echo "--> Removing WireGuard configuration directory..."
rm -rf /etc/wireguard

# --- 5. Uninstall Packages ---
echo "--> Uninstalling WireGuard and related packages..."
apt-get purge -y wireguard wireguard-tools qrencode
apt-get autoremove -y

echo ""
echo "==== WireGuard Uninstallation Complete! ===="
echo "The system has been reverted to its previous state."
echo ""
echo "Please note: Client configuration files (.conf) created in user home directories"
echo "have not been deleted. You may want to remove them manually."
echo "e.g., rm ~/*.conf"

