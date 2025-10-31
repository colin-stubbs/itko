#!/bin/sh

# WARNING: This script assumes work should occur in whatever directory it exists within.
SCRIPT_START_DIR=$(pwd)
SCRIPT_EXIST_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

cd "${SCRIPT_EXIST_DIR}"

# sane default
GEN_TEST_CERTS=${GEN_TEST_CERTS:-10}

# generate additional test certs if requested
if [ "${GEN_TEST_CERTS}x" != "x" ] && [ ${GEN_TEST_CERTS} -ge 1 ]; then

  test -s fake-ca.cfg || echo "# OpenSSL configuration file.

  [ req ]
  default_bits        = 2048
  distinguished_name  = req_distinguished_name
  prompt              = no
  # SHA-1 is deprecated, so use SHA-2 instead.
  default_md          = sha256
  # Extension to add when the -x509 option is used.
  x509_extensions     = v3_ca
  # Try to force use of PrintableString throughout
  string_mask         = pkix

  [ req_distinguished_name ]
  C=AU
  ST=Queensland
  L=Brisbane
  O=Good Roots Work
  OU=Eng
  CN=FakeCertificateAuthority

  [ v3_ca ]
  subjectKeyIdentifier = 01020304
  authorityKeyIdentifier = keyid:always,issuer
  basicConstraints = critical, CA:true, pathlen:10
  keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement, keyCertSign, cRLSign, encipherOnly, decipherOnly

  [ v3_int_ca ]
  subjectKeyIdentifier = 05060708
  authorityKeyIdentifier = keyid:always,issuer
  basicConstraints = critical, CA:true, pathlen:0
  keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement, keyCertSign, cRLSign, encipherOnly, decipherOnly
  extendedKeyUsage = serverAuth,clientAuth

  [ v3_int_ca_pair ]
  subjectKeyIdentifier = 0a0b0c0d
  authorityKeyIdentifier = keyid:always,issuer
  basicConstraints = critical, CA:true
  keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement, keyCertSign, cRLSign, encipherOnly, decipherOnly
  extendedKeyUsage = serverAuth,clientAuth

  [ v3_ca1 ]
  subjectKeyIdentifier = 11121314
  authorityKeyIdentifier = keyid:always,issuer
  basicConstraints = critical, CA:true, pathlen:10
  keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement, keyCertSign, cRLSign, encipherOnly, decipherOnly

  [ v3_user ]
  subjectKeyIdentifier = hash
  authorityKeyIdentifier = keyid:always,issuer
  keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement, encipherOnly, decipherOnly
  " > fake-ca.cfg

  test -s int-ca.cfg || echo "# OpenSSL configuration file.

  [ req ]
  default_bits        = 2048
  distinguished_name  = req_distinguished_name
  prompt              = no
  # SHA-1 is deprecated, so use SHA-2 instead.
  default_md          = sha256
  # Try to force use of PrintableString throughout
  string_mask         = pkix

  [ req_distinguished_name ]
  C=AU
  ST=Queensland
  L=Brisbane
  O=Good Roots Work
  OU=Eng
  CN=FakeIntermediateAuthority

  [ v3_user ]
  subjectKeyIdentifier = hash
  authorityKeyIdentifier = keyid:always,issuer
  keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement, encipherOnly, decipherOnly

  [ v3_user_serverAuth ]
  subjectKeyIdentifier = hash
  authorityKeyIdentifier = keyid:always,issuer
  keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement, encipherOnly, decipherOnly
  extendedKeyUsage = serverAuth

  [ v3_user_plus ]
  subjectKeyIdentifier = hash
  authorityKeyIdentifier = keyid:always,issuer
  keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement, encipherOnly, decipherOnly
  extendedKeyUsage = serverAuth,2.16.840.1.113741.1.2.3
  " > int-ca.cfg

  echo "### Creating ${GEN_TEST_CERTS} additional test leaf certificates..."
  # Create additional fake test root CA and intermediate CA if they do not already exist.
  test -f test-ca.privkey.pem || openssl ecparam -genkey -name prime256v1 -noout -out test-ca.privkey.pem 1>/dev/null 2>&1
  test -f test-ca.pem || openssl req -new -x509 -config fake-ca.cfg -set_serial 0x0406cafe -days 3650 -extensions v3_ca -inform pem -key test-ca.privkey.pem -out test-ca.pem 1>/dev/null 2>&1
  test -f test-int-ca.privkey.pem || openssl ecparam -genkey -name prime256v1 -noout -out test-int-ca.privkey.pem 1>/dev/null 2>&1
  test -f test-int-ca.csr.pem || openssl req -new -sha256 -config int-ca.cfg -key test-int-ca.privkey.pem -out test-int-ca.csr.pem 1>/dev/null 2>&1
  test -f test-int-ca.pem || openssl x509 -req -in test-int-ca.csr.pem -sha256 -extfile fake-ca.cfg -extensions v3_int_ca -CA test-ca.pem -CAkey test-ca.privkey.pem -set_serial 0x53535353 -days 3600 -out test-int-ca.pem 1>/dev/null 2>&1

  for n in `seq 1 ${GEN_TEST_CERTS}`; do
    if [ ! -s test-subleaf-${n}.chain.json ]; then
      echo "### Creating test subleaf ${n} certificate..."
      test -f test-subleaf-${n}.privkey.pem || openssl ecparam -genkey -name prime256v1 -noout -out test-subleaf-${n}.privkey.pem 1>/dev/null 2>&1
      test -f test-subleaf-${n}.csr.pem || openssl req -new -sha256 -key test-subleaf-${n}.privkey.pem -subj "/C=AU/ST=Queensland/O=Good Roots Work/OU=Eng/CN=test-subleaf-${n}.example.com" -out test-subleaf-${n}.csr.pem 1>/dev/null 2>&1
      test -f test-subleaf-${n}.pem || openssl x509 -req -in test-subleaf-${n}.csr.pem -sha256 -extfile int-ca.cfg -extensions v3_user -CA test-int-ca.pem -CAkey test-int-ca.privkey.pem -set_serial 0xdeadbeef -days 2600 -out test-subleaf-${n}.pem 1>/dev/null 2>&1
      echo "### Creating test subleaf ${n} certificate chain..."
      test -s test-subleaf-${n}.chain.json || cat test-subleaf-${n}.pem test-int-ca.pem test-ca.pem | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' > test-subleaf-${n}.chain.json
      # cleanup to minimise how disk usage/inode usage, we only really need the chain.json file.
      test -s test-subleaf-${n}.chain.json && rm -f test-subleaf-${n}.pem test-subleaf-${n}.csr.pem test-subleaf-${n}.privkey.pem
    else
      echo "### Test subleaf ${n} certificate chain already exists, skipping..."
    fi
  done
else
  echo "### ERROR: GEN_TEST_CERTS=${GEN_TEST_CERTS} which we can't understand"
fi

cd "${SCRIPT_START_DIR}"

# EOF
