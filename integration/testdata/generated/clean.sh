#!/bin/sh

# WARNING: This script assumes work should occur in whatever directory it exists within.
SCRIPT_START_DIR=$(pwd)
SCRIPT_EXIST_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

cd "${SCRIPT_EXIST_DIR}"

echo "### Cleaning up generated test data..."

# remove all generated test certs
rm -fv *.cfg *.pem *.csr *.key *.crt *.chain *.chain.json *.pre-chain *.pre-chain.json

cd "${SCRIPT_START_DIR}"

# EOF