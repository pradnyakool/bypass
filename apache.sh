#!/bin/bash
sudo su -

set -e

# === PROMPT FOR DOMAIN AND IP ===
read -p "Enter your desired domain name (e.g. dtiss.local): " DOMAIN
read -p "Enter your desired IP address (e.g. 192.168.1.100): " IP_ADDRESS

# === CONFIG ===
ROOT_CA_DIR=~/pki/root
INT_CA_DIR=~/pki/intermediate
APACHE_SSL_DIR=/etc/apache2/ssl

# === CLEAN EXISTING PKI ===
echo "🧹 Cleaning existing PKI directories..."
rm -rf $ROOT_CA_DIR $INT_CA_DIR
mkdir -p $ROOT_CA_DIR/{certs,crl,newcerts,private}
mkdir -p $INT_CA_DIR/{certs,crl,newcerts,private,csr}
touch $ROOT_CA_DIR/index.txt $INT_CA_DIR/index.txt
echo 1000 > $ROOT_CA_DIR/serial
echo 1000 > $INT_CA_DIR/serial
chmod 700 $ROOT_CA_DIR/private $INT_CA_DIR/private

# === ROOT CA CONFIG ===
cat > $ROOT_CA_DIR/openssl.cnf <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $ROOT_CA_DIR
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
private_key       = \$dir/private/ca.key.pem
certificate       = \$dir/certs/ca.cert.pem
default_md        = sha256
policy            = policy_strict
email_in_dn       = no
rand_serial       = yes

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
commonName              = supplied

[ req ]
default_bits        = 4096
default_md          = sha256
prompt              = no
distinguished_name  = dn

[ dn ]
C = IN
ST = Maharashtra
O = MyOrg
CN = MyRootCA

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

# === GENERATE ROOT CA ===
openssl genrsa -out $ROOT_CA_DIR/private/ca.key.pem 4096
openssl req -x509 -new -key $ROOT_CA_DIR/private/ca.key.pem \
    -days 3650 -out $ROOT_CA_DIR/certs/ca.cert.pem \
    -config $ROOT_CA_DIR/openssl.cnf \
    -extensions v3_ca

# === INTERMEDIATE CA CONFIG ===
cat > $INT_CA_DIR/openssl.cnf <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $INT_CA_DIR
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
private_key       = \$dir/private/intermediate.key.pem
certificate       = \$dir/certs/intermediate.cert.pem
default_md        = sha256
policy            = policy_loose
email_in_dn       = no
rand_serial       = yes

[ policy_loose ]
commonName              = supplied

[ req ]
default_bits        = 4096
default_md          = sha256
prompt              = no
distinguished_name  = dn

[ dn ]
C = IN
ST = Maharashtra
O = MyOrg
CN = MyIntermediateCA

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $DOMAIN
IP.1  = $IP_ADDRESS
EOF

# === GENERATE INTERMEDIATE CA ===
openssl genrsa -out $INT_CA_DIR/private/intermediate.key.pem 4096
openssl req -new -key $INT_CA_DIR/private/intermediate.key.pem \
    -out $INT_CA_DIR/csr/intermediate.csr.pem \
    -config $INT_CA_DIR/openssl.cnf

openssl ca -config $ROOT_CA_DIR/openssl.cnf \
    -extensions v3_ca \
    -days 1825 -notext -md sha256 \
    -in $INT_CA_DIR/csr/intermediate.csr.pem \
    -out $INT_CA_DIR/certs/intermediate.cert.pem \
    -batch

# === VERIFY INTERMEDIATE KEY MATCH ===
echo "🔍 Verifying intermediate key matches certificate..."
INT_KEY_HASH=$(openssl rsa -noout -modulus -in $INT_CA_DIR/private/intermediate.key.pem | openssl md5)
INT_CERT_HASH=$(openssl x509 -noout -modulus -in $INT_CA_DIR/certs/intermediate.cert.pem | openssl md5)
if [ "$INT_KEY_HASH" != "$INT_CERT_HASH" ]; then
  echo "❌ Intermediate key and certificate mismatch. Aborting."
  exit 1
fi

# === SERVER CSR WITH SANs ===
cat > $INT_CA_DIR/san.cnf <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = req_ext
distinguished_name = dn

[ dn ]
C = IN
ST = Maharashtra
O = MyOrg
CN = $DOMAIN

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $DOMAIN
IP.1  = $IP_ADDRESS
EOF

openssl genrsa -out $INT_CA_DIR/private/server.key.pem 2048
openssl req -new -key $INT_CA_DIR/private/server.key.pem \
    -out $INT_CA_DIR/csr/server.csr.pem \
    -config $INT_CA_DIR/san.cnf

openssl ca -config $INT_CA_DIR/openssl.cnf \
    -extensions server_cert \
    -days 365 -notext -md sha256 \
    -in $INT_CA_DIR/csr/server.csr.pem \
    -out $INT_CA_DIR/certs/server.cert.pem \
    -batch

# === APACHE HTTPS CONFIG ===
echo "🔧 Installing Apache and enabling SSL..."
sudo apt update
sudo apt install -y apache2
sudo a2enmod ssl
sudo mkdir -p $APACHE_SSL_DIR

# Copy certs to Apache
sudo cp $INT_CA_DIR/certs/server.cert.pem $APACHE_SSL_DIR/server.crt
sudo cp $INT_CA_DIR/private/server.key.pem $APACHE_SSL_DIR/server.key
sudo cp $ROOT_CA_DIR/certs/ca.cert.pem $APACHE_SSL_DIR/rootCA.crt
sudo cp $INT_CA_DIR/certs/intermediate.cert.pem $APACHE_SSL_DIR/intermediateCA.crt

# Apache SSL site config
SSL_CONF="/etc/apache2/sites-available/ssl.conf"
sudo bash -c "cat > $SSL_CONF" <<EOF
<VirtualHost $IP_ADDRESS:443>
    ServerName $DOMAIN
    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile $APACHE_SSL_DIR/server.crt
    SSLCertificateKeyFile $APACHE_SSL_DIR/server.key
    SSLCACertificateFile $APACHE_SSL_DIR/intermediateCA.crt

    <Directory /var/www/html>
        AllowOverride All
    </Directory>
</VirtualHost>
EOF

sudo a2ensite ssl.conf
sudo systemctl restart apache2

# === TRUST ROOT CA LOCALLY (Ubuntu only) ===
echo "🔐 Trusting root CA locally..."
sudo cp $ROOT_CA_DIR/certs/ca.cert.pem /usr/local/share/ca-certificates/dtiss_root.crt
sudo update-ca-certificates

echo "✅ PKI and Apache HTTPS setup complete."
echo "🌐 Visit: https://$DOMAIN or https://$IP_ADDRESS"
