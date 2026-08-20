#!/bin/bash

set -e

############################################
# Load variable file
############################################

VAR_FILE="./holodeck-vars.conf"

if [ ! -f "$VAR_FILE" ]; then
    echo "Variable file not found: $VAR_FILE"
    exit 1
fi

source "$VAR_FILE"

############################################
# Safety check
############################################

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

############################################
# Remove old nginx backup files
############################################

echo "Removing old nginx backup files..."

rm -f "${NGINX_CONF}".bak.*

############################################
# Backup nginx config
############################################

echo "Backing up nginx.conf..."

BACKUP_FILE="${NGINX_CONF}.bak.$(date +%Y%m%d-%H%M%S)"
cp "$NGINX_CONF" "$BACKUP_FILE"

echo "Backup created: $BACKUP_FILE"

############################################
# Create folders if missing
############################################

echo "Creating nginx folders if missing..."

mkdir -p "$CONF_DIR"
mkdir -p "$SSL_DIR"

############################################
# Empty existing conf.d and ssl folders
############################################

echo "Cleaning existing conf.d and ssl folders..."

rm -f "$CONF_DIR"/*.conf
rm -f "$SSL_DIR"/*.crt
rm -f "$SSL_DIR"/*.key

############################################
# Ensure nginx loads conf.d files
############################################

echo "Checking nginx include statement..."

if ! grep -q "include /etc/nginx/conf.d/\*.conf;" "$NGINX_CONF"; then
    echo "Adding conf.d include to nginx.conf..."
    sed -i '/http {/a\    include /etc/nginx/conf.d/*.conf;' "$NGINX_CONF"
else
    echo "conf.d include already exists."
fi

############################################
# Create global resolver config
############################################

echo "Creating resolver config..."

cat << EOF > "$CONF_DIR/00-holodeck-resolver.conf"
resolver $DNS_RESOLVER valid=30s;
EOF

############################################
# Function: create cert
############################################

create_cert() {
    local CERT_NAME="$1"
    local FQDN="$2"

    echo "Creating cert for $FQDN..."

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$SSL_DIR/${CERT_NAME}.key" \
        -out "$SSL_DIR/${CERT_NAME}.crt" \
        -subj "/CN=${FQDN}" \
        -addext "subjectAltName=DNS:${FQDN}"
}

############################################
# Function: create nginx reverse proxy config
############################################

create_proxy_config() {
    local CONF_NAME="$1"
    local CERT_NAME="$2"
    local FQDN="$3"
    local BACKEND="$4"

    echo "Creating nginx config for $FQDN..."

    cat << EOF > "$CONF_DIR/${CONF_NAME}.conf"
server {
    listen 443 ssl;
    server_name ${FQDN};

    ssl_certificate     ${SSL_DIR}/${CERT_NAME}.crt;
    ssl_certificate_key ${SSL_DIR}/${CERT_NAME}.key;

    location / {
        proxy_pass https://${BACKEND};

        proxy_http_version 1.1;

        proxy_set_header Host ${FQDN};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_ssl_verify off;
        proxy_ssl_server_name on;

        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
EOF
}

############################################
# VCF Management Services
############################################

create_cert "vc-mgmt" "$VC_MGMT"
create_proxy_config "vc-mgmt" "vc-mgmt" "$VC_MGMT" "$VC_MGMT"

create_cert "nsx-mgmt" "$NSX_MGMT"
create_proxy_config "nsx-mgmt" "nsx-mgmt" "$NSX_MGMT" "$NSX_MGMT"

create_cert "vcfinstaller" "$VCF_INSTALLER"
create_proxy_config "vcfinstaller" "vcfinstaller" "$VCF_INSTALLER" "$VCF_INSTALLER"

create_cert "ops" "$OPS"
create_proxy_config "ops" "ops" "$OPS" "$OPS"

############################################
# Workload Domain Services
############################################

create_cert "vc-wld01" "$VC_WLD01"
create_proxy_config "vc-wld01" "vc-wld01" "$VC_WLD01" "$VC_WLD01"

create_cert "nsx-wld01" "$NSX_WLD01"
create_proxy_config "nsx-wld01" "nsx-wld01" "$NSX_WLD01" "$NSX_WLD01"

############################################
# ESXi Hosts
############################################

create_cert "esx-01" "$ESX_01"
create_proxy_config "esx-01" "esx-01" "$ESX_01" "$ESX_01"

create_cert "esx-02" "$ESX_02"
create_proxy_config "esx-02" "esx-02" "$ESX_02" "$ESX_02"

create_cert "esx-03" "$ESX_03"
create_proxy_config "esx-03" "esx-03" "$ESX_03" "$ESX_03"

create_cert "esx-04" "$ESX_04"
create_proxy_config "esx-04" "esx-04" "$ESX_04" "$ESX_04"

create_cert "esx-05" "$ESX_05"
create_proxy_config "esx-05" "esx-05" "$ESX_05" "$ESX_05"

create_cert "esx-06" "$ESX_06"
create_proxy_config "esx-06" "esx-06" "$ESX_06" "$ESX_06"

create_cert "esx-07" "$ESX_07"
create_proxy_config "esx-07" "esx-07" "$ESX_07" "$ESX_07"

############################################
# Enable SSH forwarding on HoloRouter
############################################

echo "Enabling SSH forwarding..."

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_BACKUP="${SSHD_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"

cp "$SSHD_CONFIG" "$SSHD_BACKUP"

echo "SSH config backup created: $SSHD_BACKUP"

set_sshd_option() {
    local OPTION="$1"
    local VALUE="$2"

    if grep -qE "^[# ]*${OPTION}" "$SSHD_CONFIG"; then
        sed -i "s|^[# ]*${OPTION}.*|${OPTION} ${VALUE}|g" "$SSHD_CONFIG"
    else
        echo "${OPTION} ${VALUE}" >> "$SSHD_CONFIG"
    fi
}

set_sshd_option "AllowTcpForwarding" "yes"
set_sshd_option "GatewayPorts" "yes"
set_sshd_option "PermitTunnel" "yes"

echo "Restarting SSH service..."

if systemctl list-unit-files | grep -q "^sshd.service"; then
    systemctl restart sshd
elif systemctl list-unit-files | grep -q "^ssh.service"; then
    systemctl restart ssh
else
    service sshd restart || service ssh restart
fi

############################################
# Test nginx
############################################

echo "Testing nginx config..."

nginx -t

############################################
# Reload nginx
############################################

echo "Reloading nginx..."

systemctl reload nginx || service nginx reload

############################################
# Print Windows hosts file entries
############################################

echo ""
echo "============================================"
echo "Add these entries to your Windows hosts file:"
echo "C:\\Windows\\System32\\drivers\\etc\\hosts"
echo "============================================"
echo ""

cat << EOF
# HoloRouter
${HOLROUTER_IP} ${HOLROUTER_HOSTNAME}

# VCF Management
${HOLROUTER_IP} ${VC_MGMT}
${HOLROUTER_IP} ${NSX_MGMT}
${HOLROUTER_IP} ${SDDC_MGR}
${HOLROUTER_IP} ${VCF_INSTALLER}
${HOLROUTER_IP} ${OPS}

# Workload Domain
${HOLROUTER_IP} ${VC_WLD01}
${HOLROUTER_IP} ${NSX_WLD01}

# ESXi Hosts
${HOLROUTER_IP} ${ESX_01}
${HOLROUTER_IP} ${ESX_02}
${HOLROUTER_IP} ${ESX_03}
${HOLROUTER_IP} ${ESX_04}
${HOLROUTER_IP} ${ESX_05}
${HOLROUTER_IP} ${ESX_06}
${HOLROUTER_IP} ${ESX_07}
EOF

echo ""
echo "============================================"
echo "Done."
echo "After updating Windows hosts file, run:"
echo "ipconfig /flushdns"
echo "============================================"
