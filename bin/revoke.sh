#!/bin/bash
set -e

CERT_NAME=$1
CERT_SERIAL=$2

EASY_RSA=${EASY_RSA_PATH:-"/usr/share/easy-rsa"}
OPENVPN_DIR=${OPENVPN_DIR:-"/etc/openvpn"}

echo "EasyRSA path: $EASY_RSA OVPN path: $OPENVPN_DIR"
INDEX=$EASY_RSA/pki/index.txt
OVPN_FILE_PATH="$OPENVPN_DIR/clients/$CERT_NAME.ovpn"

export EASYRSA_BATCH=1

if [[ -z $CERT_NAME ]]; then
    echo "Usage: $0 <client_name> [serial]"
    exit 1
fi

cd $EASY_RSA

echo "Revoking certificate $CERT_NAME..."
# Use --batch to avoid interactive prompts
if ! ./easyrsa --batch revoke "$CERT_NAME"; then
    echo "Standard revocation failed with 'name does not match'. Attempting forced manual revocation..."
    
    # 1. Try manual openssl with a clean config
    TMP_CONF="/tmp/revoke.cnf"
    cat > "$TMP_CONF" <<EOF
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = $OPENVPN_DIR/pki
database = \$dir/index.txt
certificate = \$dir/ca.crt
private_key = \$dir/private/ca.key
new_certs_dir = \$dir/issued
serial = \$dir/serial
crl = \$dir/crl.pem
RANDFILE = \$dir/.rand
default_md = sha256
policy = policy_anything
[ policy_anything ]
countryName = optional
stateOrProvinceName = optional
localityName = optional
organizationName = optional
organizationalUnitName = optional
commonName = supplied
name = optional
emailAddress = optional
EOF

    if ! openssl ca -utf8 -config "$TMP_CONF" -revoke "$OPENVPN_DIR/pki/issued/$CERT_NAME.crt"; then
        echo "OpenSSL manual revocation failed. Using the 'nuclear option': direct index.txt manipulation..."
        
        # 2. Direct manipulation of index.txt (The ultimate fallback)
        # Format: Status(1) [TAB] Expiration(2) [TAB] RevocationDate(3) [TAB] Serial(4) [TAB] Filename(5) [TAB] Subject(6)
        REV_DATE=$(date -u +%y%m%d%H%M%SZ)
        INDEX_FILE="$OPENVPN_DIR/pki/index.txt"
        
        # We use awk to find the line by CN and precisely set columns 1 (Status) and 3 (Revocation Date)
        # We use \t as separator to preserve the file structure exactly
        awk -v cn="/CN=$CERT_NAME/" -v date="$REV_DATE" 'BEGIN {FS="\t"; OFS="\t"} {
            if ($6 ~ cn && $1 == "V") {
                $1="R";
                $3=date;
            }
            print $0
        }' "$INDEX_FILE" > "${INDEX_FILE}.tmp" && mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
        
        echo "index.txt manually updated for $CERT_NAME with date $REV_DATE."
    fi
    rm -f "$TMP_CONF"
fi

echo "Generating new CRL..."
# We use easyrsa to generate CRL, it will read our updated index.txt
./easyrsa --batch gen-crl
cp -f $EASY_RSA/pki/crl.pem $OPENVPN_DIR/pki/crl.pem
chmod +r $OPENVPN_DIR/pki/crl.pem

echo "Removing .ovpn file..."
rm -f "$OVPN_FILE_PATH"

echo "Done! Restart OpenVPN to apply changes if necessary."
