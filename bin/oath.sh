#!/bin/sh
PASSFILE=$1
OPENVPN_DIR=/etc/openvpn
OATH_SECRETS=$OPENVPN_DIR/clients/oath.secrets
LOG_FILE=/var/log/openvpn/oath.log

user=$(head -1 $PASSFILE)
pass=$(tail -1 $PASSFILE) 

echo "$(date) - 2FA authentication attempt for user $user" | tee -a $LOG_FILE

secret=$(grep -i -m 1 "$user:" $OATH_SECRETS | cut -d: -f2)

code=$(oathtool --totp $secret)

if [ "$code" = "$pass" ];
then
    echo "OK"
        exit 0
else 
echo "FAIL"
fi

echo "$(date) - 2FA authentication failed for user $user" | tee -a $LOG_FILE
exit 1