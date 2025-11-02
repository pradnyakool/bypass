#!/bin/bash

echo "enter directory"
read dir
mkdir $dir
cd $dir
echo "enter 1st user name (sender)"
read user1
echo "enter 2nd user name (reciver)"
read user2

openssl genpkey -algorithm RSA -out $user1.private.pem -aes256
#chmod 777 $user1.private.pem
echo "private key generated for" $user1
openssl rsa -pubout -in $user1.private.pem -out $user1.public.pem
#chmod 777 $user1.public.pem
echo "public key generated for" $user1

openssl genpkey -algorithm RSA -out $user2.private.pem -aes256
echo "private key generated for" $user2
#chmod 777 $user2.private.pem
openssl rsa -pubout -in $user2.private.pem -out $user2.public.pem
echo "public generated for" $user2
#chmod 777 $user1.public.pem

echo "enter message to encrypt"
read msg
echo $msg > message.txt

openssl dgst -sha256 -sign $user1.private.pem -out message.sig message.txt
echo "hash generated from $user1 private key"

openssl pkeyutl -encrypt -in message.txt -inkey $user2.public.pem -pubin -out message.enc -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256
echo "message encrypted with $user2 public key"

openssl pkeyutl -decrypt -in message.enc -inkey $user2.private.pem -out decrypted.txt -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256
echo "message decrypted by $user2 with $user2 private key"

openssl dgst -sha256 -verify $user1.public.pem -signature message.sig message_dec.txt
echo "signature verified by $user2"

#mkdir $user1
#mkdir $user2

#mv $user1.private.pem $user1/
#mv $user1.public.pem $user1/
#mv message.txt $user1/
#mv message.sig $user1/
#mv message.enc $user2/
#mv decrypted.txt $user2/
#mv $user2.private.pem $user2/
#mv $user2.private.pem $user2/
