#!/bin/bash

# This script sets up a WireGuard VPN server on Ubuntu.
# It should be run with root privileges.

# --- Exit on error ---
set -e

# --- Check for root privileges ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

echo "==== Starting WireGuard Setup ===="

# --- 1. Package Update and Installation ---
echo "--> Updating package list and upgrading existing packages..."
apt-get update
apt-get upgrade -y

echo "--> Installing WireGuard and qrencode..."
apt-get install -y wireguard qrencode

# --- 2. Key Pair Generation ---
echo "--> Generating server and client key pairs..."
mkdir -p /etc/wireguard
cd /etc/wireguard

# Generate server keys
wg genkey | tee server_private_key | wg pubkey > server_public_key
# Generate client keys
wg genkey | tee client_private_key | wg pubkey > client_public_key

# Set permissions
chmod 600 server_private_key client_private_key

# Read keys into variables
SERVER_PRIVATE_KEY=$(cat server_private_key)
SERVER_PUBLIC_KEY=$(cat server_public_key)
CLIENT_PRIVATE_KEY=$(cat client_private_key)
CLIENT_PUBLIC_KEY=$(cat client_public_key)

# --- 3. Server Configuration ---
echo "--> Configuring WireGuard server (wg0.conf)..."
SERVER_IP_ADDR=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP_ADDR" ]; then
    echo "Could not automatically determine the server's public IP address." >&2
    read -p "Please enter the server's public IP address: " SERVER_IP_ADDR
fi

cat > /etc/wireguard/wg0.conf << EOL
[Interface]
Address = 10.0.0.1/24
SaveConfig = true
PrivateKey = ${SERVER_PRIVATE_KEY}
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o $(ip -o -4 route show to default | awk '{print $5}') -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o $(ip -o -4 route show to default | awk '{print $5}') -j MASQUERADE

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = 10.0.0.2/32
EOL

# --- 4. Network Configuration ---
echo "--> Enabling IP forwarding..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

# --- 5. Firewall Configuration ---
echo "--> Configuring firewall with ufw..."
echo "--> Allowing packet forwarding for ufw..."
# By default, ufw blocks all packet forwarding. This needs to be enabled for the VPN to work.
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
ufw reload
ufw allow 51820/udp
ufw allow 22/tcp
ufw --force enable
ufw status

# --- 6. Client Configuration ---
echo "--> Creating client configuration (client.conf)..."
# The client config will be created in the home directory of the user who ran the script with sudo
SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
CLIENT_CONFIG_PATH="${SUDO_USER_HOME}/client.conf"

cat > "${CLIENT_CONFIG_PATH}" << EOL
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = 10.0.0.2/32
DNS = 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_IP_ADDR}:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOL

# --- 7. Service Enable and Start ---
echo "--> Enabling and starting WireGuard service..."
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0
systemctl status wg-quick@wg0 --no-pager

# --- 8. Display Results ---
echo ""
echo "==== WireGuard Setup Complete! ===="
echo "Client configuration file created at: ${CLIENT_CONFIG_PATH}"
echo ""
echo "--- Client Configuration ---"
cat "${CLIENT_CONFIG_PATH}"
echo "----------------------------"
echo ""
echo "--- QR Code for Mobile Client ---"
qrencode -t ansiutf8 < "${CLIENT_CONFIG_PATH}"
echo "---------------------------------"
echo "Scan the QR code with your WireGuard mobile app."
echo "To add more clients, run the 'add_client.sh' script."
