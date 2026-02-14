#!/bin/bash
set -e

EASY_RSA=/usr/share/easy-rsa
OPENVPN_DIR=/etc/openvpn
UI_DIR=/opt/openvpn-ui
APP_DIR=/opt/app

parse_cidr() {
    local cidr=${1:-$2}
    local ip=$(echo $cidr | cut -d/ -f1)
    local bits=$(echo $cidr | cut -d/ -f2)
    local mask=""
    case $bits in
        32) mask="255.255.255.255" ;;
        24) mask="255.255.255.0" ;;
        16) mask="255.255.0.0" ;;
        8)  mask="255.0.0.0" ;;
        *)  mask="255.255.255.0" ;;
    esac
    echo "$ip $mask $cidr"
}

read OVPN_SERVER_NETWORK OVPN_SERVER_NETMASK TRUST_SUB <<< $(parse_cidr "${OVPN_NETWORK}" "10.0.70.0/24")
read OVPN_GUEST_NETWORK OVPN_GUEST_NETMASK GUEST_SUB <<< $(parse_cidr "${OVPN_GUEST_NETWORK}" "10.0.71.0/24")
read OVPN_HOME_NETWORK OVPN_HOME_NETMASK HOME_SUB <<< $(parse_cidr "${OVPN_HOME_NETWORK}" "192.168.88.0/24")

export OVPN_SERVER_NETWORK OVPN_SERVER_NETMASK TRUST_SUB
export OVPN_GUEST_NETWORK OVPN_GUEST_NETMASK GUEST_SUB
export OVPN_HOME_NETWORK OVPN_HOME_NETMASK HOME_SUB


mkdir -p "$OPENVPN_DIR/pki" "$OPENVPN_DIR/clients" "$OPENVPN_DIR/db" "$OPENVPN_DIR/log" "$OPENVPN_DIR/config" "$OPENVPN_DIR/staticclients"

mkdir -p /opt/scripts
ln -sf "$APP_DIR/bin/genclient.sh" /opt/scripts/genclient.sh
ln -sf "$APP_DIR/bin/genclient.sh" /opt/scripts/generate_client.sh
ln -sf "$APP_DIR/bin/revoke.sh" /opt/scripts/revoke.sh
ln -sf "$APP_DIR/bin/revoke.sh" /opt/scripts/revoke_client.sh
ln -sf "$APP_DIR/bin/rmcert.sh" /opt/scripts/rmcert.sh
ln -sf "$APP_DIR/bin/rmcert.sh" /opt/scripts/rmcert_client.sh
ln -sf "$APP_DIR/bin/oath.sh" /opt/scripts/oath.sh
ln -sf "$APP_DIR/bin/oath-sec-gen.sh" /opt/scripts/oath-sec-gen.sh

if [[ ! -f "$OPENVPN_DIR/server.conf" ]]; then
    echo "Initial run: creating default server.conf..."
    cp "$APP_DIR/server.conf" "$OPENVPN_DIR/server.conf"
fi

if [[ -z "$(ls -A "$OPENVPN_DIR/config")" ]]; then
    echo "Initial run: populating config templates..."
    cp -r "$APP_DIR/config/." "$OPENVPN_DIR/config/"
fi

if [[ -f "$OPENVPN_DIR/config/client.conf" ]]; then
    CURRENT_REMOTE=$(grep "^remote " "$OPENVPN_DIR/config/client.conf" | awk '{print $2}')
    TARGET_REMOTE=${OVPN_REMOTE_HOST:-"127.0.0.1"}
    if [[ "$CURRENT_REMOTE" != "$TARGET_REMOTE" ]] && [[ "$CURRENT_REMOTE" != "\${OVPN_REMOTE_HOST}" ]]; then
        echo "Updating client.conf template: $CURRENT_REMOTE -> $TARGET_REMOTE"
        sed -i "s|^remote .* 1194|remote $TARGET_REMOTE 1194|g" "$OPENVPN_DIR/config/client.conf"
    fi
fi

LOG_DIR="/var/log/openvpn"
mkdir -p "$LOG_DIR"
touch "$LOG_DIR/openvpn.log"
chmod 755 "$LOG_DIR"
chmod 644 "$LOG_DIR/openvpn.log"

echo "EasyRSA path: $EASY_RSA OVPN path: $OPENVPN_DIR"

export EASYRSA_REQ_COUNTRY=${EASYRSA_REQ_COUNTRY:-KZ}
export EASYRSA_REQ_PROVINCE=${EASYRSA_REQ_PROVINCE:-AT}
export EASYRSA_REQ_CITY=${EASYRSA_REQ_CITY:-Astana}
export EASYRSA_REQ_ORG=${EASYRSA_REQ_ORG:-AstanaHome}
export EASYRSA_REQ_EMAIL=${EASYRSA_REQ_EMAIL:-vpn@astana.kz}
export EASYRSA_REQ_OU=${EASYRSA_REQ_OU:-MyOrganizationalUnit}
export EASYRSA_REQ_CN=${EASYRSA_REQ_CN:-OpenVPNServer}
export EASYRSA_KEY_SIZE=${EASYRSA_KEY_SIZE:-2048}
export EASYRSA_CA_EXPIRE=${EASYRSA_CA_EXPIRE:-3650}
export EASYRSA_CERT_EXPIRE=${EASYRSA_CERT_EXPIRE:-825}
export EASYRSA_CERT_RENEW=${EASYRSA_CERT_RENEW:-30}
export EASYRSA_CRL_DAYS=${EASYRSA_CRL_DAYS:-180}

sed -e "s|\${EASYRSA_REQ_COUNTRY}|$EASYRSA_REQ_COUNTRY|g" \
    -e "s|\${EASYRSA_REQ_PROVINCE}|$EASYRSA_REQ_PROVINCE|g" \
    -e "s|\${EASYRSA_REQ_CITY}|$EASYRSA_REQ_CITY|g" \
    -e "s|\${EASYRSA_REQ_ORG}|$EASYRSA_REQ_ORG|g" \
    -e "s|\${EASYRSA_REQ_EMAIL}|$EASYRSA_REQ_EMAIL|g" \
    -e "s|\${EASYRSA_REQ_OU}|$EASYRSA_REQ_OU|g" \
    -e "s|\${EASYRSA_REQ_CN}|$EASYRSA_REQ_CN|g" \
    -e "s|\${EASYRSA_KEY_SIZE}|$EASYRSA_KEY_SIZE|g" \
    -e "s|\${EASYRSA_CA_EXPIRE}|$EASYRSA_CA_EXPIRE|g" \
    -e "s|\${EASYRSA_CERT_EXPIRE}|$EASYRSA_CERT_EXPIRE|g" \
    -e "s|\${EASYRSA_CERT_RENEW}|$EASYRSA_CERT_RENEW|g" \
    -e "s|\${EASYRSA_CRL_DAYS}|$EASYRSA_CRL_DAYS|g" \
    "$APP_DIR/config/easy-rsa.vars" > "$OPENVPN_DIR/config/easy-rsa.vars"

if [[ ! -f $OPENVPN_DIR/pki/ca.crt ]]; then
    export EASYRSA_BATCH=1
    cd $EASY_RSA
    echo 'Setting up public key infrastructure...'
    $EASY_RSA/easyrsa init-pki
    cp $OPENVPN_DIR/config/easy-rsa.vars $EASY_RSA/pki/vars
    echo 'Generating ertificate authority...'
    $EASY_RSA/easyrsa build-ca nopass
    echo 'Creating the Server Certificate...'
    $EASY_RSA/easyrsa gen-req server nopass
    echo 'Sign request...'
    $EASY_RSA/easyrsa sign-req server server
    cp -rf $EASY_RSA/pki/* $OPENVPN_DIR/pki/
    cp -f $EASY_RSA/pki/vars $OPENVPN_DIR/pki/vars
    echo 'Generate Diffie-Hellman key (fast mode)...'
    openssl dhparam -dsaparam -out $EASY_RSA/pki/dh.pem 2048
    echo 'Generate HMAC signature...'
    openvpn --genkey --secret $EASY_RSA/pki/ta.key
    echo 'Create certificate revocation list (CRL)...'
    $EASY_RSA/easyrsa gen-crl
    chmod +r $EASY_RSA/pki/crl.pem
    cp -rf $EASY_RSA/pki/* $OPENVPN_DIR/pki/
fi

if [ -d "$EASY_RSA/pki" ] && [ ! -L "$EASY_RSA/pki" ]; then rm -rf "$EASY_RSA/pki"; fi
ln -sf "$OPENVPN_DIR/pki" "$EASY_RSA/pki"

if [ -d "$OPENVPN_DIR/pki/vars" ]; then rm -rf "$OPENVPN_DIR/pki/vars"; fi
cp -f "$OPENVPN_DIR/config/easy-rsa.vars" "$OPENVPN_DIR/pki/vars"

mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

echo "Configuring iptables..."
# Get default interface
EXT_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
if [[ -z "$EXT_IF" ]]; then
    EXT_IF="eth0"
fi

# Enable NAT
iptables -t nat -A POSTROUTING -s "$TRUST_SUB" -o "$EXT_IF" -j MASQUERADE || iptables -t nat -A POSTROUTING -s "$TRUST_SUB" -j MASQUERADE
iptables -t nat -A POSTROUTING -s "$GUEST_SUB" -o "$EXT_IF" -j MASQUERADE || iptables -t nat -A POSTROUTING -s "$GUEST_SUB" -j MASQUERADE

# Allow Forwarding
iptables -A FORWARD -i tun+ -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Guest isolation and restrictions
iptables -A FORWARD -p icmp -j DROP --icmp-type echo-request -s "$GUEST_SUB" || true
iptables -A FORWARD -p icmp -j DROP --icmp-type echo-reply -s "$GUEST_SUB" || true
iptables -A FORWARD -s "$GUEST_SUB" -d "$HOME_SUB" -j DROP || true

if [[ -s "$OPENVPN_DIR/config/fw-rules.sh" ]]; then
    source "$OPENVPN_DIR/config/fw-rules.sh"
elif [[ -s "$APP_DIR/bin/fw-rules.sh" ]]; then
    source "$APP_DIR/bin/fw-rules.sh"
fi

export OVPN_DNS_1=${OVPN_DNS_1:-8.8.8.8}
export OVPN_DNS_2=${OVPN_DNS_2:-1.0.0.1}

sed -e "s|\${OVPN_SERVER_NETWORK}|$OVPN_SERVER_NETWORK|g" \
    -e "s|\${OVPN_SERVER_NETMASK}|$OVPN_SERVER_NETMASK|g" \
    -e "s|\${OVPN_GUEST_NETWORK}|$OVPN_GUEST_NETWORK|g" \
    -e "s|\${OVPN_GUEST_NETMASK}|$OVPN_GUEST_NETMASK|g" \
    -e "s|\${OVPN_HOME_NETWORK}|$OVPN_HOME_NETWORK|g" \
    -e "s|\${OVPN_HOME_NETMASK}|$OVPN_HOME_NETMASK|g" \
    -e "s|\${OVPN_DNS_1}|$OVPN_DNS_1|g" \
    -e "s|\${OVPN_DNS_2}|$OVPN_DNS_2|g" \
    "$APP_DIR/server.conf" > "$OPENVPN_DIR/server.conf"

echo 'Preparing OpenVPN UI...'
export OVPN_REMOTE_HOST=${OVPN_REMOTE_HOST:-"127.0.0.1"}
export OPENVPN_ADMIN_USERNAME=${OPENVPN_ADMIN_USERNAME:-admin}
export OPENVPN_ADMIN_PASSWORD=${OPENVPN_ADMIN_PASSWORD:-admin}

# Export variables for UI binary compatibility (all possible variants)
export REQ_COUNTRY=${EASYRSA_REQ_COUNTRY}
export REQ_PROVINCE=${EASYRSA_REQ_PROVINCE}
export REQ_CITY=${EASYRSA_REQ_CITY}
export REQ_ORG=${EASYRSA_REQ_ORG}
export REQ_EMAIL=${EASYRSA_REQ_EMAIL}
export REQ_OU=${EASYRSA_REQ_OU}
export REQ_CN=${EASYRSA_REQ_CN}

# Some versions of UI use these
export EASY_RSA_REQ_COUNTRY=${EASYRSA_REQ_COUNTRY}
export EASY_RSA_REQ_PROVINCE=${EASYRSA_REQ_PROVINCE}
export EASY_RSA_REQ_CITY=${EASYRSA_REQ_CITY}
export EASY_RSA_REQ_ORG=${EASYRSA_REQ_ORG}
export EASY_RSA_REQ_EMAIL=${EASYRSA_REQ_EMAIL}
export EASY_RSA_REQ_OU=${EASYRSA_REQ_OU}
export EASY_RSA_REQ_CN=${EASYRSA_REQ_CN}

export EASY_RSA_PATH=/usr/share/easy-rsa
export OPENVPN_CONFIG_PATH=$OPENVPN_DIR/server.conf
export OPENVPN_PKI_PATH=/usr/share/easy-rsa/pki

sed -i "s/openvpn:2080/localhost:2080/g" $UI_DIR/conf/app.conf

if [ -L "$UI_DIR/db" ]; then rm "$UI_DIR/db"; fi
mkdir -p "$UI_DIR/db"

# Background task to sync UI database with environment variables
(
    # Wait for the DB file to be created by the UI app
    # The UI app uses ./db/data.db in its default config
    DB_FILE="$UI_DIR/db/data.db"
    for i in $(seq 1 30); do
        if [ -f "$DB_FILE" ]; then
            echo "UI Database found. Applying custom EasyRSA settings (KZ) to the UI..."
            sqlite3 "$DB_FILE" "UPDATE easy_r_s_a_config SET \
                easy_r_s_a_req_country='${EASYRSA_REQ_COUNTRY}', \
                easy_r_s_a_req_province='${EASYRSA_REQ_PROVINCE}', \
                easy_r_s_a_req_city='${EASYRSA_REQ_CITY}', \
                easy_r_s_a_req_org='${EASYRSA_REQ_ORG}', \
                easy_r_s_a_req_email='${EASYRSA_REQ_EMAIL}', \
                easy_r_s_a_req_ou='${EASYRSA_REQ_OU}', \
                easy_r_s_a_req_cn='${EASYRSA_REQ_CN}' \
                WHERE profile='default';" || echo "Warning: Could not update UI database via sqlite3."
            break
        fi
        sleep 1
    done
) &

cd "$UI_DIR"
./openvpn-ui &

echo "Starting OpenVPN..."
tail -f /var/log/openvpn/openvpn.log &
/usr/sbin/openvpn --cd "$OPENVPN_DIR" --management localhost 2080 --script-security 2 --config "$OPENVPN_DIR/server.conf"
