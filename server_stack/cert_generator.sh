# Generate a private key
openssl genpkey -algorithm RSA -out keys/private_key.pem -aes256

# Create a configuration file for the certificate
cat > keys/openssl.cnf <<EOF
[ req ]
default_bits = 2048
default_keyfile = keys/private_key.pem
distinguished_name = req_distinguished_name
x509_extensions = v3_req

[ req_distinguished_name ]
countryName = Country Name (2 letter code)
countryName_default = US
stateOrProvinceName = State or Province Name (full name)
stateOrProvinceName_default = Some-State
localityName = Locality Name (eg, city)
localityName_default = Some-City
organizationName = Organization Name (eg, company)
organizationName_default = Example Inc.
commonName = Common Name (e.g. server FQDN or YOUR name)
commonName_default = example.com
commonName_max = 64

[ v3_req ]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
EOF

# Generate a self-signed certificate with domain information
openssl req -new -x509 -key keys/private_key.pem -out keys/ssl_cert.pem -days 365 -config keys/openssl.cnf

# Generate Diffie-Hellman parameters
openssl dhparam -out keys/dhparam.key 2048

# Generate a self-signed CA certificate
openssl req -new -x509 -key keys/private_key.pem -out keys/ca.crt -days 365 -config keys/openssl.cnf

# Adjust file permissions
chmod 600 keys/private_key.pem
chmod 644 keys/ssl_cert.pem
chmod 644 keys/dhparam.key
chmod 644 keys/ca.crt
