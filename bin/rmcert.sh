#!/bin/bash
set -e

CERT_NAME=$1
CERT_SERIAL=$2

EASY_RSA=${EASY_RSA_PATH:-"/usr/share/easy-rsa"}
OPENVPN_DIR=${OPENVPN_DIR:-"/etc/openvpn"}

echo "EasyRSA path: $EASY_RSA OVPN path: $OPENVPN_DIR"
INDEX="$EASY_RSA/pki/index.txt"
OVPN_FILE_PATH="$OPENVPN_DIR/clients/$CERT_NAME.ovpn"
QR_CODE_PATH="$OPENVPN_DIR/clients/$CERT_NAME.png"

if [[ -z $CERT_NAME ]]; then
    echo "Usage: $0 <client_name> [serial]"
    exit 1
fi

echo "Removing certificate files for $CERT_NAME..."
rm -f "$OVPN_FILE_PATH"
rm -f "$QR_CODE_PATH"

if [[ ! -z $CERT_SERIAL ]]; then
    echo "Removing serial $CERT_SERIAL from database..."
    sed -i "/$CERT_SERIAL/d" "$INDEX"
fi

echo "Done!"
