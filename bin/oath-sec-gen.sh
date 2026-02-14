#!/bin/sh

TFA_NAME=$1
OPENVPN_DIR=/etc/openvpn
OATH_SECRETS=$OPENVPN_DIR/clients/oath.secrets

ISSUER='MFA%20OpenVPN'

USERHASH=$(head -c 10 /dev/urandom | openssl sha256 | cut -d ' ' -f2 | cut -b 1-30)

BASE32=$(/usr/bin/oathtool --totp -v "$USERHASH" | grep Base32 | awk '{print $3}')

QRSTRING="otpauth://totp/$ISSUER:$TFA_NAME?secret=$BASE32"
echo "User String for QR:"
echo $QRSTRING

qrencode $QRSTRING -o $OPENVPN_DIR/clients/$TFA_NAME.png

echo "oath.secrets entry for BackEnd:"
echo "$TFA_NAME:$USERHASH" | tee -a $OATH_SECRETS
