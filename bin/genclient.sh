#!/bin/bash
set -e

CERT_NAME=$1
CERT_IP=${2:-""}
CERT_PASS=${3:-""}

EASY_RSA=${EASY_RSA_PATH:-"/usr/share/easy-rsa"}
OPENVPN_DIR=${OPENVPN_DIR:-"/etc/openvpn"}

echo "EasyRSA path: $EASY_RSA OVPN path: $OPENVPN_DIR"
OVPN_FILE_PATH="$OPENVPN_DIR/clients/$CERT_NAME.ovpn"
OATH_SECRETS="$OPENVPN_DIR/clients/oath.secrets"

if [[ -z $CERT_NAME ]]; then
    echo 'Name cannot be empty. Exiting...'
    exit 1
fi

export EASYRSA_BATCH=1

echo 'Generate client certificate...'
cd $EASY_RSA

if [[ -z $CERT_PASS ]]; then
    echo 'Without password...'
    ./easyrsa --batch --req-cn="$CERT_NAME" gen-req "$CERT_NAME" nopass 
else
    echo 'With password...'
    (echo -e "$CERT_PASS\n$CERT_PASS") | ./easyrsa --batch --req-cn="$CERT_NAME" gen-req "$CERT_NAME"
fi

./easyrsa sign-req client "$CERT_NAME"

TFA_NAME=${TFA_NAME:-"none"}

echo "Fixing Database..."
sed -i "/\/CN=$CERT_NAME\//s/$/\/name=${CERT_NAME}\/LocalIP=${CERT_IP}\/2FAName=${TFA_NAME}/" $EASY_RSA/pki/index.txt

CA="$(cat $EASY_RSA/pki/ca.crt )"
CERT="$(openssl x509 -in $EASY_RSA/pki/issued/${CERT_NAME}.crt)"
KEY="$(cat $EASY_RSA/pki/private/${CERT_NAME}.key)"
TLS_CRYPT="$(cat $EASY_RSA/pki/ta.key)"

echo "Generating .ovpn file for $CERT_NAME..."
OVPN_REMOTE_HOST=${OVPN_REMOTE_HOST:-"127.0.0.1"}
CLIENT_TEMPLATE="$OPENVPN_DIR/config/client.conf"

if [ -f "$CLIENT_TEMPLATE" ]; then
    cat "$CLIENT_TEMPLATE"
    sed -e "s|\${OVPN_REMOTE_HOST}|$OVPN_REMOTE_HOST|g" \
        -e "s|^remote 127.0.0.1 |remote $OVPN_REMOTE_HOST |g" \
        "$CLIENT_TEMPLATE" > "$OVPN_FILE_PATH"
else
    echo "client.conf template not found, creating basic config"
    echo "client
dev tun
proto udp
remote $OVPN_REMOTE_HOST 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA512
verb 3" > "$OVPN_FILE_PATH"
fi

echo "DEBUG: Content of generated .ovpn file for $CERT_NAME:"
cat "$OVPN_FILE_PATH"

echo "
<ca>
$CA
</ca>
<cert>
$CERT
</cert>
<key>
$KEY
</key>
<tls-crypt>
$TLS_CRYPT
</tls-crypt>
" >> "$OVPN_FILE_PATH"

echo -e "OpenVPN Client configuration successfully generated!\nPath: $OVPN_FILE_PATH"

if [[ ! -z $TFA_NAME ]] && [[ $TFA_NAME != "none" ]]; then
    echo -e "Generating 2FA ...\nName: $TFA_NAME"
    USERHASH=$(head -c 10 /dev/urandom | openssl sha256 | cut -d ' ' -f2 | cut -b 1-30)
    BASE32=$(oathtool --totp -v "$USERHASH" | grep Base32 | awk '{print $3}')
    QRSTRING="otpauth://totp/${TFA_ISSUER:-OpenVPN}:$TFA_NAME?secret=$BASE32"
    echo "User String for QR: $QRSTRING"
    if command -v qrencode >/dev/null 2>&1; then
        qrencode "$QRSTRING" -o "$OPENVPN_DIR/clients/$CERT_NAME.png"
    fi
    echo "$TFA_NAME:$USERHASH" >> "$OATH_SECRETS"
fi

