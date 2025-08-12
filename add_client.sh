#!/bin/bash

# This script adds a new client to the WireGuard setup.
# It should be run with root privileges.

# --- Exit on error ---
set -e

# --- Check for root privileges ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# --- Check for WireGuard config ---
if [ ! -f /etc/wireguard/wg0.conf ]; then
    echo "/etc/wireguard/wg0.conf not found. Please run the setup script first." >&2
    exit 1
fi

# --- Get Client Name ---
if [ -z "$1" ]; then
    read -p "Enter a name for the new client (e.g., my-phone): " CLIENT_NAME
else
    CLIENT_NAME=$1
fi

if [ -z "$CLIENT_NAME" ]; then
    echo "Client name cannot be empty." >&2
    exit 1
fi

# Check if client name already exists
if grep -q "# Client: ${CLIENT_NAME}" /etc/wireguard/wg0.conf; then
    echo "Client '${CLIENT_NAME}' already exists." >&2
    exit 1
fi


# --- Allocate IP Address ---
# Find the last used IP address and increment it
LAST_IP=$(grep 'AllowedIPs' /etc/wireguard/wg0.conf | tail -n1 | awk -F '[ ./]' '{print $6}')
if [ -z "$LAST_IP" ]; then
    # If no peer exists yet, start with the first client IP
    NEW_IP="10.0.0.2"
else
    # Increment the last octet
    NEW_IP="10.0.0.$((LAST_IP + 1))"
fi

echo "--> New client '${CLIENT_NAME}' will be assigned IP: ${NEW_IP}"

# --- Generate Key Pair ---
echo "--> Generating key pair for ${CLIENT_NAME}..."
cd /etc/wireguard
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "${CLIENT_PRIVATE_KEY}" | wg pubkey)

# --- Update Server Configuration ---
echo "--> Updating server configuration..."
# Add the new peer to wg0.conf to make it persistent
cat >> /etc/wireguard/wg0.conf << EOL

# Client: ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${NEW_IP}/32
EOL

# Apply the new peer configuration dynamically to the running interface
wg set wg0 peer "${CLIENT_PUBLIC_KEY}" allowed-ips "${NEW_IP}/32"

echo "--> Server configuration updated successfully."

# --- Generate Client Configuration ---
echo "--> Creating client configuration file..."
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public_key)
# Determine the server's public IP address for the client endpoint.
SERVER_ENDPOINT=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_ENDPOINT" ]; then
    echo "Could not automatically determine the server's public IP address." >&2
    read -p "Please enter the server's public IP address: " SERVER_ENDPOINT
fi


SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
CLIENT_CONFIG_PATH="${SUDO_USER_HOME}/${CLIENT_NAME}.conf"

cat > "${CLIENT_CONFIG_PATH}" << EOL
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${NEW_IP}/32
DNS = 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_ENDPOINT}:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOL

# --- Display Results ---
echo ""
echo "==== New Client Added Successfully! ===="
echo "Client configuration file created at: ${CLIENT_CONFIG_PATH}"
echo ""
echo "--- Client Configuration (${CLIENT_NAME}) ---"
cat "${CLIENT_CONFIG_PATH}"
echo "---------------------------------------"
echo ""
echo "--- QR Code for Mobile Client ---"
qrencode -t ansiutf8 < "${CLIENT_CONFIG_PATH}"
echo "---------------------------------"
echo "Scan the QR code with your WireGuard mobile app."
