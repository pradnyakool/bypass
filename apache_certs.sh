
#!/bin/bash
echo "enter a dir name"
read dirname

mkdir $dirname
cd $dirname 
echo "Enter Root Key name"
read root_key
sudo openssl genpkey -algorithm RSA -out $root_key.key -pkeyopt rsa_keygen_bits:4096
echo $root_key.key
echo "root Key Generated"
echo "Enter Root Certificate Name"
read root_cer
sudo openssl req -x509 -new -nodes -key $root_key.key -sha256 -days 3650 -out $root_cer.crt

echo "Enter SubCA key name"
read subCA_key
sudo openssl genpkey -algorithm RSA -out $subCA_key.key -pkeyopt rsa_keygen_bits:4096
echo "subCA Key Generated"
echo "Enter SubCA Certificate Name"
read subCA_cer
sudo openssl req -new -key $subCA_key.key -out $subCA_cer.csr

sudo openssl x509 -req -in $subCA_cer.csr -CA $root_cer.crt -CAkey $root_key.key -CAcreateserial -out $subCA_cer.crt -days 3650 -sha256

echo "subCA Certificate Generated"

echo "Enter Personal that is your domain name key Name"
read personal_key
sudo openssl genpkey -algorithm RSA -out $personal_key.key -pkeyopt rsa_keygen_bits:2048
echo "Domain or Perosnal Key Generated"
echo "Enter Domain or Personal Certificate Name"
read personal_cert
sudo openssl req -new -key $personal_key.key -out $personal_cert.csr

sudo openssl x509 -req -in $personal_cert.csr -CA $subCA_cer.crt -CAkey $subCA_key.key -CAcreateserial -out $personal_cert.crt -days 365 -sha256
rm -f $subCA_cer.csr $personal_cert.csr  $root_cer.srl
mkdir keys
mkdir certs

mv $root_key.key keys/$root_key.key
mv $subCA_key.key keys/$subCA_key.key
mv $personal_key.key keys/$personal_key.key

mv $root_cer.crt certs/$root_cer.crt
mv $subCA_cer.crt certs/$subCA_cer.crt
mv $personal_cert.crt certs/$personal_cert.crt
