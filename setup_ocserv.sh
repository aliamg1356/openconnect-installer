#!/bin/bash

# === Define Colors ===
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# === Logo Function ===
display_logo() {
    echo -e "${YELLOW}
    ██╗   ██╗████████╗██╗   ██╗███╗   ██╗███╗   ██╗███████╗██╗     
    ██║   ██║╚══██╔══╝██║   ██║████╗  ██║████╗  ██║██╔════╝██║     
    ██║   ██║   ██║   ██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██║     
    ██║   ██║   ██║   ██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██║     
    ╚██████╔╝   ██║   ╚██████╔╝██║ ╚████║██║ ╚████║███████╗███████╗
     ╚═════╝    ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚══════╝                                                                
              ushkayanet openconnect-installer console
    ${NC}"
}

clear
display_logo
sleep 2

# === Dependency Check ===
echo "[✔] Checking required packages..."
for cmd in docker docker-compose curl certbot; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "[✘] $cmd not found. Installing..."
    apt update && apt install -y $cmd
  else
    echo "[✔] $cmd is installed."
  fi
done

# === User Inputs ===
read -p "Enter your domain (e.g., vpn.example.com): " DOMAIN
read -p "Enter your email for Let's Encrypt certificate: " EMAIL
read -p "Enter VPN subnet (e.g., 172.16.10.0): " VPN_SUBNET
read -p "Enter RADIUS server IP: " RADIUS_IP
read -sp "Enter RADIUS shared secret: " RADIUS_SECRET
echo ""
read -p "Enter VPN port number [default: 443]: " VPN_PORT
VPN_PORT=${VPN_PORT:-443}

# === Get SSL Certificate ===
echo "[✔] Getting SSL certificate for $DOMAIN..."
certbot certonly --standalone -d "$DOMAIN" --agree-tos -n --email "$EMAIL"
if [ $? -ne 0 ]; then
  echo "[✘] Failed to get SSL certificate. Exiting."
  exit 1
fi

# === Create Directory Structure ===
mkdir -p /opt/ocs/{config,radius,certs}

# === Copy Certificates ===
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /opt/ocs/certs/fullchain.pem
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /opt/ocs/certs/privkey.pem

# === Download and Load Docker Image ===
echo "[✔] Downloading Docker image..."
curl -L -o /opt/ocs/ushkayanet-ocservlatest.tar https://github.com/aliamg1356/openconnect-installer/releases/download/v1.0.0/ushkayanet-ocservlatest.tar

echo "[✔] Loading Docker image..."
docker load -i /opt/ocs/ushkayanet-ocservlatest.tar

# === Create docker-compose.yml ===
cat <<EOF > /opt/ocs/docker-compose.yml
services:
  ocserv:
    image: ushkayanet-ocserv:latest
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
    networks:
      shared_net:
        ipv4_address: 172.20.0.3

networks:
  shared_net:
    external: true
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

# === Download Dictionary Files ===
echo "[✔] Downloading Radius dictionary files..."
DICTIONARY_FILES=(dictionary dictionary.ascend dictionary.compat dictionary.merit dictionary.microsoft dictionary.roaringpenguin dictionary.sip)
BASE_URL="https://raw.githubusercontent.com/aliamg1356/openconnect-installer/refs/heads/main"
for file in "${DICTIONARY_FILES[@]}"; do
  curl -sSL "$BASE_URL/$file" -o "/opt/ocs/radius/$file"
done

# === Start the container ===
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

# === Setup cronjob for every Saturday 4 AM ===
(crontab -l 2>/dev/null; echo "0 4 * * 6 /opt/ocs/renew_ssl.sh >> /opt/ocs/renew_ssl.log 2>&1") | crontab -

# === Completion Message ===
echo -e "\n\033[1;32m✔ VPN setup complete!\033[0m"
echo ""
printf "%-20s | %-40s\n" "Field" "Value"
printf -- "---------------------+------------------------------------------\n"
printf "%-20s | %-40s\n" "Domain" "$DOMAIN"
printf "%-20s | %-40s\n" "VPN Port" "$VPN_PORT"
printf "%-20s | %-40s\n" "VPN Subnet" "$VPN_SUBNET"
printf "%-20s | %-40s\n" "RADIUS Server" "$RADIUS_IP"
printf "%-20s | %-40s\n" "Docker Image" "ushkayanet-ocserv:latest"
printf "%-20s | %-40s\n" "Auto-Renew" "Every Saturday at 4:00 AM"
echo ""
