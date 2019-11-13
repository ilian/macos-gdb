#!/usr/bin/env bash
set -ex

CERT="org.gnu.gdb"

check_gdb() {
  if ! [ -x "$(command -v gdb)" ]; then
    echo 'Error: gdb is not installed. You can install gdb using Homebrew: https://brew.sh' >&2
    exit 1
  fi
}

# Install codeSigning cert
# Credits to https://github.com/derekparker/delve/blob/master/scripts/gencert.sh
install_cert() {
    # Check if the certificate is already present in the system keychain
    security find-certificate -Z -p -c "$CERT" /Library/Keychains/System.keychain > /dev/null 2>&1
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ]; then
      # Certificate has already been generated and installed
      return 0
    fi

    # Create the certificate template
    cat <<EOF >$CERT.tmpl
[ req ]
default_bits       = 2048        # RSA key size
encrypt_key        = no          # Protect private key
default_md         = sha512      # MD to use
prompt             = no          # Prompt for DN
distinguished_name = codesign_dn # DN template
[ codesign_dn ]
commonName         = "$CERT"
[ codesign_reqext ]
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
EOF

    # Generate a new certificate
    openssl req -new -newkey rsa:2048 -x509 -days 3650 -nodes -config $CERT.tmpl -extensions codesign_reqext -batch -out $CERT.cer -keyout $CERT.key > /dev/null 2>&1
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
      # Something went wrong when generating the certificate
      return 1
    fi

    # Install the certificate in the system keychain
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CERT.cer > /dev/null 2>&1
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
      # Something went wrong when installing the certificate
      return 1
    fi

    # Install the key for the certificate in the system keychain
    sudo security import $CERT.key -A -k /Library/Keychains/System.keychain > /dev/null 2>&1
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
      # Something went wrong when installing the key
      return 1
    fi

    # Kill task_for_pid access control daemon
    sudo pkill -f /usr/libexec/taskgated > /dev/null 2>&1

    # Remove generated files
    rm $CERT.tmpl $CERT.cer $CERT.key > /dev/null 2>&1

    # Exit indicating the certificate is now generated and installed
    return 0
}

sign() {
    entitlement=$(mktemp)
    cat - >"$entitlement" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.debugger</key>
    <true/>
</dict>
</plist>
EOF
    codesign --entitlement "$entitlement" -fs "$CERT" "$(which gdb)"
}

check_gdb
set +e
install_cert
set -e
sign
