#!/bin/sh

export CTLOG_NAME=itko-submit
export CTLOG_SUBMISSION_BASE_URL=http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1

if [ "${LOAD_TEST_DATA}x" = "truex" ] ; then
  cd /itko/testdata

  echo "### Merging test data roots to CT log trusted roots..."
  TMP_FILE=$(mktemp)

  # we need to do this here to ensure the test-ca is generated before we merge the trusted roots, but we don't want to generate too many certs yet so we overrride with 1.
  GEN_TEST_CERTS=1 /itko/testdata/generate.sh

  # merge existing and test CA's as unique trusted roots. This needs to happen before ${CTLOG_NAME} starts.
  mkdir -p "${ITKO_ROOT_DIRECTORY}/ct/v1"
  test -f ${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots && cat "${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots" 2>/dev/null | jq --raw-output '.certificates[]' 2>/dev/null > "${TMP_FILE}"
  for i in `find /itko -type f -name fake-ca\*.cert -o -type f -name test-ca.pem` ; do
    test -f "${i}" || continue
    cat "${i}" 2>/dev/null | tr  -d '\n' | sed -r -E -e 's/-+END CERTIFICATE-+BEGIN CERTIFICATE-+/\n/g' -e 's/-+END CERTIFICATE-+$/\n/' -e 's/-+BEGIN CERTIFICATE-+//' >> "${TMP_FILE}"
  done

  # use the combined but unique list of trusted roots to update the CT log trusted roots.
  cat "${TMP_FILE}" | sort -u | jq --raw-input --monochrome-output --compact-output --slurp 'split("\n") | map(select(length > 0)) | {certificates: .}' > "${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots"
fi

# run testdata/insert.sh script - this runs in the background and *should* perform a loop waiting until ${CTLOG_NAME} has started before doing *things*.
test -f /itko/testdata/insert.sh && /itko/testdata/insert.sh


# EOF
