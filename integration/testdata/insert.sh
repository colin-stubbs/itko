#!/bin/sh

# WARNING: This script assumes work should occur in whatever directory it exists within.
SCRIPT_START_DIR=$(pwd)
SCRIPT_EXIST_DIR=$( cd -- "$( dirname -- "$0" )" &> /dev/null && pwd )

cd "${SCRIPT_EXIST_DIR}"

LOAD_TEST_DATA=${LOAD_TEST_DATA:-false}
# compact ndjson chain file to support very large numbers of certs/chains.
CERT_CHAINS_NDJSON=${CERT_CHAINS_NDJSON:-compact.chains.ndjson}
# sane default, how many certs to load from ${CERT_CHAINS_NDJSON} if it exists.
LOAD_GENERATED_CERTS=${LOAD_GENERATED_CERTS:-}

if [ "${LOAD_TEST_DATA}x" = "truex" ] ; then
  echo "### Loading test data..."

  # run generate script to generate fresh extra test certs if it exists and is executable.
  # NOTE: generate.sh will not generate new certs unless ${CERT_CHAINS_NDJSON} is empty or does not have enough.
  test -x generate.sh && ./generate.sh

  echo -n "### Waiting for ${CTLOG_NAME} to start and respond to HTTP requests..."
  while ! curl -s "${CTLOG_SUBMISSION_BASE_URL}/add-chain" >/dev/null 2>&1; do
    sleep 1
    echo -n "."
  done
  echo "OK!"

  echo "### ${CTLOG_NAME} started and responding to HTTP requests..."

  # generate JSON chains from known current leaf certs if they exist
  test -s subleaf.chain && cat subleaf.chain | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > subleaf.chain.json
  test -s subleaf-pre.chain && cat subleaf-pre.chain | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > subleaf-pre.pre-chain.json

  # generate JSON chains for all other available leaf certs in current directory
  for i in leaf*.chain ; do
    test -f ${i} && cat ${i} | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > ${i}.json
  done

  # attempt to log issued certs to CT log
  find . -type f -name \*.chain.json -exec curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d '@{}' "${CTLOG_SUBMISSION_BASE_URL}/add-chain" \; 1>/dev/null 2>&1

  # attempt to log pre-certs to CT log
  find . -type f -name \*.pre-chain.json -exec curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d '@{}' "${CTLOG_SUBMISSION_BASE_URL}/add-pre-chain" \; 1>/dev/null 2>&1

  if [ "${LOAD_GENERATED_CERTS}x" != "x" ] && [ "${LOAD_GENERATED_CERTS}" -gt 0 ] && [ -s "${CERT_CHAINS_NDJSON}" ] ; then
    echo "### Loading ${LOAD_GENERATED_CERTS} certificate chains from ${CERT_CHAINS_NDJSON}..."
    COUNT=1
    head -n ${LOAD_GENERATED_CERTS} "${CERT_CHAINS_NDJSON}" | while read -r line; do
      echo "### Adding certificate chain ${COUNT} to CT log..."
      curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d "${line}" "${CTLOG_SUBMISSION_BASE_URL}/add-chain"
      echo
      COUNT=$((COUNT + 1))
    done
  fi

  rm -f "${TMP_FILE}"
fi

cd "${SCRIPT_START_DIR}"

# EOF
