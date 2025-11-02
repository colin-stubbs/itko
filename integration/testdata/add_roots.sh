#!/bin/sh

# WARNING: This script assumes work should occur in whatever directory it exists within.
SCRIPT_START_DIR=$(pwd)
SCRIPT_EXIST_DIR=$( cd -- "$( dirname -- "$0" )" &> /dev/null && pwd )

cd "${SCRIPT_EXIST_DIR}"

echo "### Merging test data roots to CT log trusted roots..."

TMP_FILE=$(mktemp)

# merge existing and test CA's as unique trusted roots. This needs to happen before itko-submit starts.
cat "${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots" 2>/dev/null | jq --raw-output '.certificates[]' 2>/dev/null > "${TMP_FILE}"
cat fake-ca*.cert generated/test-ca.pem 2>/dev/null | tr  -d '\n' | sed -r -E -e 's/-+END CERTIFICATE-+BEGIN CERTIFICATE-+/\n/g' -e 's/-+END CERTIFICATE-+$/\n/' -e 's/-+BEGIN CERTIFICATE-+//' >> "${TMP_FILE}"
cat "${TMP_FILE}" | sort -u | jq --raw-input --monochrome-output --compact-output --slurp 'split("\n") | map(select(length > 0)) | {certificates: .}' > "${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots"

rm -f "${TMP_FILE}"

cd "${SCRIPT_START_DIR}"

# EOF
