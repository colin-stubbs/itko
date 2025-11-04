#!/bin/sh

# WARNING: This script assumes work should occur in whatever directory it exists within.
SCRIPT_START_DIR=$(pwd)
SCRIPT_EXIST_DIR=$( cd -- "$( dirname -- "$0" )" &> /dev/null && pwd )

cd "${SCRIPT_EXIST_DIR}"

# compact ndjson chain file to support very large numbers of certs/chains.
COMPACT_CHAINS_NDJSON=${COMPACT_CHAINS_NDJSON:-compact.chains.ndjson}
# sane default, how many certs to load from ${COMPACT_CHAINS_NDJSON} if it exists.
LOAD_GENERATED_CERTS=${LOAD_GENERATED_CERTS:-10}

if [ ${LOAD_TEST_DATA} = "true" ] ; then
  echo "### Loading test data..."

  # run generate script to generate fresh extra test certs if it exists and is executable.
  test -x generate.sh && ./generate.sh

  echo "### Merging test data roots to CT log trusted roots..."
  TMP_FILE=$(mktemp)

  # merge existing and test CA's as unique trusted roots. This needs to happen before itko-submit starts.
  cat "${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots" 2>/dev/null | jq --raw-output '.certificates[]' 2>/dev/null > "${TMP_FILE}"
  cat fake-ca*.cert test-ca.pem 2>/dev/null | tr  -d '\n' | sed -r -E -e 's/-+END CERTIFICATE-+BEGIN CERTIFICATE-+/\n/g' -e 's/-+END CERTIFICATE-+$/\n/' -e 's/-+BEGIN CERTIFICATE-+//' >> "${TMP_FILE}"

  # use the combined but unique list of trusted roots to update the CT log trusted roots.
  cat "${TMP_FILE}" | sort -u | jq --raw-input --monochrome-output --compact-output --slurp 'split("\n") | map(select(length > 0)) | {certificates: .}' > "${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots"

  # it's possible that the generate.sh script finished after supervisord has already started itko-submit, 
  # so we use a kill to ensure itko-submit is restarted (automatically by supervisord) so it can pick up the new trusted roots.
  killall -9 itko-submit 2>/dev/null || true

  echo -n "### Waiting for itko-submit to start and respond to HTTP requests..."
  while ! curl -s http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1/add-chain >/dev/null 2>&1; do
    sleep 1
    echo -n "."
  done
  echo "OK!"

  echo "### itko-submit started and responding to HTTP requests..."

  # generate JSON chains from known current leaf certs if they exist
  test -s subleaf.chain && cat subleaf.chain | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > subleaf.chain.json
  test -s subleaf-pre.chain && cat subleaf-pre.chain | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > subleaf-pre.pre-chain.json

  # generate JSON chains for all other available leaf certs in current directory
  for i in leaf*.chain ; do
    test -f ${i} && cat ${i} | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > ${i}.json
  done

  # attempt to log issued certs to CT log
  find . -type f -name \*.chain.json -exec curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d '@{}' "http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1/add-chain" \; 1>/dev/null 2>&1

  # attempt to log pre-certs to CT log
  find . -type f -name \*.pre-chain.json -exec curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d '@{}' "http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1/add-pre-chain" \; 1>/dev/null 2>&1

  if [ -s "${COMPACT_CHAINS_NDJSON}" ] ; then
    echo "### Loading ${LOAD_GENERATED_CERTS} certificate chains from ${COMPACT_CHAINS_NDJSON}..."
    COUNT=1
    head -n ${LOAD_GENERATED_CERTS} "${COMPACT_CHAINS_NDJSON}" | while read -r line; do
      echo "### Adding certificate chain ${COUNT} to CT log..."
      curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d "${line}" "http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1/add-chain" 1>/dev/null 2>&1
      echo
    done
  fi

  rm -f "${TMP_FILE}"
fi

cd "${SCRIPT_START_DIR}"

# EOF
