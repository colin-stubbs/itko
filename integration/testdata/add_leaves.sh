#!/bin/sh

# WARNING: This script assumes work should occur in whatever directory it exists within.
SCRIPT_START_DIR=$(pwd)
SCRIPT_EXIST_DIR=$( cd -- "$( dirname -- "$0" )" &> /dev/null && pwd )

cd "${SCRIPT_EXIST_DIR}"

# generate JSON chains from known current leaf certs if they exist
test -s subleaf.chain && cat subleaf.chain | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > subleaf.chain.json
test -s subleaf-pre.chain && cat subleaf-pre.chain | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > subleaf-pre.pre-chain.json

# generate JSON chains for all other available leaf certs in current directory
for i in leaf*.chain ; do
  test -f ${i} && cat ${i} | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > ${i}.json
done

# attempt to log issued certs to CT log
for i in `find . -type f -name \*.chain.json`; do
  echo -n "### Adding chain ${i} to log..."
  curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d "@${i}" "http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1/add-chain" && echo -n "... OK!"
  echo
done

# attempt to log pre-certs to CT log
for i in `find . -type f -name \*.pre-chain.json`; do
  echo -n "### Adding pre-chain ${i} to log..."
  curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d "@${i}" "http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1/add-pre-chain" && echo -n "... OK!"
  echo
done

cd "${SCRIPT_START_DIR}"

# EOF
