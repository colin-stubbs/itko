#!/bin/sh

# WARNING: This script assumes work should occur in whatever directory it exists within.
SCRIPT_START_DIR=$(pwd)
SCRIPT_EXIST_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

cd "${SCRIPT_EXIST_DIR}"

echo "### Building trusted roots from testdata..."

# add all of our fake test CA's as trusted roots. This needs to happen before itko-submit starts.
test -s ${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots || cat fake-ca*.cert generated/test-ca.cert 2>/dev/nll | tr  -d '\n' | sed -E -e 's/^/{"certificates":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' > ${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots

cd "${SCRIPT_START_DIR}"

# EOF
