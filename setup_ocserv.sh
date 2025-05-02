#!/bin/bash

# == Ushkaya Net ASCII Logo ==
echo "   _    _ _     _               _             "
echo "  | |  | (_)   | |             | |            "
echo "  | |  | |_  __| | ___ _ __ ___| |_ ___  _ __ "
echo "  | |  | | |/ _\` |/ _ \ '__/ __| __/ _ \| '__|"
echo "  | |__| | | (_| |  __/ |  \__ \ || (_) | |   "
echo "   \____/|_|\__,_|\___|_|  |___/\__\___/|_|   "
echo "                                             "
echo "                Ushkaya Net"
sleep 2

# == Dependency Check ==
echo "[✔] Checking required packages..."
for cmd in docker docker-compose curl certbot whiptail; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "[✘] $cmd not found. Installing..."
    apt update && apt install -y $cmd
  else
    echo "[✔] $cmd is installed."
  fi
done

# == User Inputs ==
DOMAIN=$(whiptail --title " Domain Name" --inputbox "Enter your domain (vpn.example.com):" 10 60 3>&1 1>&2 2>&3)
EMAIL=$(whiptail --title " Email" --inputbox "Enter your email for Let's Encrypt certificate:" 10 60 3>&1 1>&2 2>&3)
VPN_SUBNET=$(whiptail --title " VPN Subnet" --inputbox "Enter VPN subnet (exm:172.16.10.0):" 10 60 3>&1 1>&2 2>&3)
RADIUS_IP=$(whiptail --title " RADIUS Server IP" --inputbox "Enter RADIUS server IP (exm:10.20.30.40):" 10 60 3>&1 1>&2 2>&3)
RADIUS_SECRET=$(whiptail --title " RADIUS Secret" --passwordbox "Enter RADIUS shared secret:" 10 60 3>&1 1>&2 2>&3)

# == Obtain SSL Certificate ==
echo "[✔] Getting SSL certificate from Let's Encrypt for $DOMAIN..."
certbot certonly --standalone -d "$DOMAIN" --agree-tos -n --email "$EMAIL"
if [ $? -ne 0 ]; then
  whiptail --title "❌ Error" --msgbox "Failed to get SSL certificate. Exiting." 10 50
  exit 1
fi

# == Create Directory Structure ==
mkdir -p /opt/ocs/{config,radius}

# == Create docker-compose.yml ==
cat <<EOF > /opt/ocs/docker-compose.yml
services:
  ocserv:
    image: snipking/docker-ocserv-radius
    container_name: ocserv
    privileged: true
    ports:
      - "443:443/tcp"
      - "443:443/udp"
    volumes:
      - ./config:/etc/ocserv
      - ./radius:/etc/radcli
      - /etc/letsencrypt/live/$DOMAIN/fullchain.pem:/etc/ocserv/certs/fullchain.pem:ro
      - /etc/letsencrypt/live/$DOMAIN/privkey.pem:/etc/ocserv/certs/privkey.pem:ro
    cap_add:
      - NET_ADMIN
    restart: unless-stopped
EOF

# == Create ocserv config ==
cat <<EOF > /opt/ocs/config/ocserv.conf
auth = "radius[config=/etc/radcli/radiusclient.conf,groupconfig=true]"
acct = "radius[config=/etc/radcli/radiusclient.conf,groupconfig=true]"
tcp-port = 443
server-cert = /etc/ocserv/certs/fullchain.pem
server-key = /etc/ocserv/certs/privkey.pem
ca-cert = /etc/ssl/certs/ssl-cert-snakeoil.pem
isolate-workers = true
max-same-clients = 10
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

# == Create radcli files ==
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

# == Completion Message ==
whiptail --title " Setup Complete" --msgbox "Everything is ready.\n\nNext step:\ncd /opt/ocs && docker-compose up -d" 12 60
