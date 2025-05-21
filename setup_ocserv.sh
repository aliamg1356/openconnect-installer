#!/bin/bash

# === Ushkaya Net ASCII Logo ===
echo "   _    _ _     _               _             "
echo "  | |  | | |   | |             | |            "
echo "  | |  | | | __| | ___ _ __ ___| |_ ___  _ __ "
echo "  | |  | | |/ _\` |/ _ \ '__/ __| __/ _ \| '__|"
echo "  | |__| | | (_| |  __/ |  \__ \ || (_) | |   "
echo "   \____/|_|\__,_|\___|_|  |___/\__\___/|_|   "
echo "                                             "
echo "                Ushkaya Net"
sleep 2

# === Dependency Check ===
echo "[✔] Checking required packages..."
for cmd in docker docker-compose curl certbot whiptail; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "[✘] $cmd not found. Installing..."
    apt update && apt install -y $cmd
  else
    echo "[✔] $cmd is installed."
  fi
done

# === User Inputs ===
DOMAIN=$(whiptail --title " Domain Name" --inputbox "Enter your domain (vpn.example.com):" 10 60 3>&1 1>&2 2>&3)
EMAIL=$(whiptail --title " Email" --inputbox "Enter your email for Let's Encrypt certificate:" 10 60 3>&1 1>&2 2>&3)
VPN_SUBNET=$(whiptail --title " VPN Subnet" --inputbox "Enter VPN subnet (e.g.: 172.16.10.0):" 10 60 3>&1 1>&2 2>&3)
RADIUS_IP=$(whiptail --title " RADIUS Server IP" --inputbox "Enter RADIUS server IP:" 10 60 3>&1 1>&2 2>&3)
RADIUS_SECRET=$(whiptail --title " RADIUS Secret" --passwordbox "Enter RADIUS shared secret:" 10 60 3>&1 1>&2 2>&3)
VPN_PORT=$(whiptail --title " VPN Port" --inputbox "Enter VPN port number (default:443):" 10 60 "443" 3>&1 1>&2 2>&3)

# === Get SSL Certificate ===
echo "[✔] Getting SSL certificate from Let's Encrypt for $DOMAIN..."
certbot certonly --standalone -d "$DOMAIN" --agree-tos -n --email "$EMAIL"
if [ $? -ne 0 ]; then
  whiptail --title "❌ Error" --msgbox "Failed to get SSL certificate. Exiting." 10 50
  exit 1
fi

# === Create Directory Structure ===
mkdir -p /opt/ocs/{config,radius,certs}

# === Copy Initial Certificates ===
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /opt/ocs/certs/fullchain.pem
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /opt/ocs/certs/privkey.pem

# === Create docker-compose.yml ===
cat <<EOF > /opt/ocs/docker-compose.yml
services:
  ocserv:
    image: snipking/docker-ocserv-radius
    container_name: ocserv
    privileged: true
    ports:
      - "$VPN_PORT:443/tcp"
      - "$VPN_PORT:443/udp"
    volumes:
      - ./config:/etc/ocserv
      - ./radius:/etc/radcli
      - ./certs:/etc/ocserv/certs
    cap_add:
      - NET_ADMIN
    restart: unless-stopped
EOF

# === Create ocserv.conf ===
cat <<EOF > /opt/ocs/config/ocserv.conf
auth = "radius[config=/etc/radcli/radiusclient.conf,groupconfig=true]"
acct = "radius[config=/etc/radcli/radiusclient.conf,groupconfig=true]"
tcp-port = 443
udp-port = 443
run-as-user = nobody
run-as-group = daemon
socket-file = /run/ocserv.socket
server-cert = /etc/ocserv/certs/fullchain.pem
server-key = /etc/ocserv/certs/privkey.pem
ca-cert = /etc/ssl/certs/ssl-cert-snakeoil.pem
isolate-workers = true
max-clients = 254
max-same-clients = 10
server-stats-reset-time = 604800
keepalive = 30
dpd = 60
mobile-dpd = 300
switch-to-tcp-timeout = 25
try-mtu-discovery = true
cert-user-oid = 0.9.2342.19200300.100.1.1
compression = true
no-compress-limit = 256
tls-priorities = "NORMAL:%SERVER_PRECEDENCE:%COMPAT:-RSA:-VERS-SSL3.0:-ARCFOUR-128"
auth-timeout = 40
min-reauth-time = 2
max-ban-score = 0
ban-reset-time = 300
cookie-timeout = 300
deny-roaming = false
rekey-time = 172800
rekey-method = ssl
use-occtl = true
pid-file = /run/ocserv.pid
device = vpns
predictable-ips = true
default-domain = $DOMAIN
ipv4-network = $VPN_SUBNET
ipv4-netmask = 255.255.255.0
tunnel-all-dns = true
dns = 94.140.14.14
dns = 94.140.15.15
ping-leases = false
cisco-client-compat = true
dtls-legacy = true
EOF

# === Create radcli config ===
cat <<EOF > /opt/ocs/radius/radiusclient.conf
auth_order radius
login_tries 4
login_timeout 60
nologin /etc/nologin
servers /etc/radcli/servers
authserver $RADIUS_IP
acctserver $RADIUS_IP
dictionary /etc/radcli/dictionary
login_radius /usr/sbin/login.radius
seqfile /var/run/radius.seq
mapfile /etc/radcli/port-id-map
default_realm
radius_timeout 10
radius_retries 3
EOF

echo "$RADIUS_IP $RADIUS_SECRET" > /opt/ocs/radius/servers

# === Download Radius Dictionary Files ===
echo "[✔] Downloading Radius dictionary files..."
DICTIONARY_FILES=(
    "dictionary"
    "dictionary.ascend"
    "dictionary.compat"
    "dictionary.merit"
    "dictionary.microsoft"
    "dictionary.roaringpenguin"
    "dictionary.sip"
)

BASE_URL="https://raw.githubusercontent.com/aliamg1356/openconnect-installer/refs/heads/main"

for file in "${DICTIONARY_FILES[@]}"; do
    curl -sSL "$BASE_URL/$file" -o "/opt/ocs/radius/$file"
done

# === Start Docker Container ===
cd /opt/ocs && docker-compose up -d

# === Create SSL Auto-Renew Script ===
cat <<EOF > /opt/ocs/renew_ssl.sh
#!/bin/bash

echo "[+] Renewing certificate for $DOMAIN..."
certbot renew --quiet

if [ \$? -eq 0 ]; then
    echo "[+] Copying updated certificates..."
    cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /opt/ocs/certs/fullchain.pem
    cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /opt/ocs/certs/privkey.pem
    docker restart ocserv
else
    echo "[!] Certificate renewal failed."
fi
EOF

chmod +x /opt/ocs/renew_ssl.sh

# === Setup cronjob for auto-renew every Saturday at 4AM ===
(crontab -l 2>/dev/null; echo "0 4 * * 6 /opt/ocs/renew_ssl.sh >> /opt/ocs/renew_ssl.log 2>&1") | crontab -

# === Completion Message ===
whiptail --title "✅ Setup Complete" --msgbox "OpenConnect VPN setup is complete!\n\nDomain: $DOMAIN\nVPN Port: $VPN_PORT\nVPN Subnet: $VPN_SUBNET\nRADIUS Server: $RADIUS_IP\n\nAutomatic SSL renewal is scheduled every Saturday at 04:00." 15 60
