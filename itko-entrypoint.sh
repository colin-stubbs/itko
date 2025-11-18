#!/bin/sh

# itko-entrypoint.sh

# ensure all variables are set with sane defaults.
# Consul configuration, refer to /usr/local/bin/consul-entrypoint.sh or https://hub.docker.com/_/consul/
export CONSUL_BIND_ADDRESS=${CONSUL_BIND_ADDRESS:-127.0.0.1}
export CONSUL_BIND_INTERFACE=${CONSUL_BIND_INTERFACE:-lo}
export CONSUL_CLIENT_ADDRESS=${CONSUL_CLIENT_ADDRESS:-127.0.0.1}
export CONSUL_CLIENT_INTERFACE=${CONSUL_CLIENT_INTERFACE:-lo}
export CONSUL_LOCAL_CONFIG=${CONSUL_LOCAL_CONFIG:-{"datacenter":"dev","server":true,"enable_debug":false}}

# set to true to load test certs from testdata/
export LOAD_TEST_DATA=${LOAD_TEST_DATA:-false}
# set to 1+ to auto-generate certificates, NOTE: this is dependent upon LOAD_TEST_DATA being true and will not occur if LOAD_TEST_DATA is false.
export GEN_TEST_CERTS=${GEN_TEST_CERTS:-}

# Itko configuration, refer to the remainder of this script to understand how these are used.
export ITKO_KV_PATH=${ITKO_KV_PATH:-itko}
export ITKO_ROOT_DIRECTORY=${ITKO_ROOT_DIRECTORY:-/itko/ct/storage}
export ITKO_KEY_PATH=${ITKO_KEY_PATH:-/itko/testdata/ct-http-server.privkey.plaintext.pem}
export ITKO_LOG_NAME=${ITKO_LOG_NAME:-testlog}
export ITKO_LOG_ID=${ITKO_LOG_ID:-lrviNpCI/wLGL5VTfK25b8cOdbP0YA7tGoQak5jST9o=}
export ITKO_LOG_PUBLIC_KEY=${ITKO_LOG_PUBLIC_KEY:-MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEB/hRr6qMVoOQMbeA49Ya9y82BnHs3Tu+fjZvDRwcYAt/9Z//5SRJNFbySxBfvwgf+Q7PNbWKioswClS3vx1NuQ==}
export ITKO_LOG_SUBMISSION_URL=${ITKO_LOG_SUBMISSION_URL:-http://itko:3030/}
export ITKO_LOG_MONITORING_URL=${ITKO_LOG_MONITORING_URL:-http://itko:3031/}
export ITKO_MASK_SIZE=${ITKO_MASK_SIZE:-5}
export ITKO_FLUSH_MS=${ITKO_FLUSH_MS:-50}
export ITKO_SUBMIT_LISTEN_ADDRESS=${ITKO_SUBMIT_LISTEN_ADDRESS:-0.0.0.0}
export ITKO_SUBMIT_LISTEN_PORT=${ITKO_SUBMIT_LISTEN_PORT:-3030}
export ITKO_MONITOR_LISTEN_ADDRESS=${ITKO_MONITOR_LISTEN_ADDRESS:-0.0.0.0}
export ITKO_MONITOR_LISTEN_PORT=${ITKO_MONITOR_LISTEN_PORT:-3031}

# used locally in script for our generated monitor*.json files
# The current date/time in simple UTC zoned RFC3339 format, used in our generated monitor.json files if we're auto-generating them.
NOW=`date -u -Iseconds | sed -r 's/\+00:00/Z/'`
# Used in our generated monitor.json files if we're auto-generating them, e.g. a long time ago in a galaxy far, far away...
NOT_AFTER_START="2000-01-01T00:00:00Z"
# Used in our generated monitor.json files if we're auto-generating them, e.g. now + years in simple UTC zoned RFC3339 format.
NOT_AFTER_LIMIT="`date -d \"$(($(date +%Y)+10))-$(date +%m)-$(date +%d)\" -I`T00:00:00Z"

# control curl's behaviour, retry up to 10 times with a 1 second delay between retries.
export CURL_EXTRA_ARGS="--retry-connrefused --retry-all-errors --retry-delay 1 --retry 10"

# if DEBUG is set to true, dump the environment and enable verbose curl output.
if [ "${DEBUG}x" == "truex" ]; then
  echo "#### Environment ####"
  env | sort
  echo "####################"
  CURL_EXTRA_ARGS="${CURL_EXTRA_ARGS} --verbose"
else
  CURL_EXTRA_ARGS="${CURL_EXTRA_ARGS} --silent"
fi

## Now, ensure all dependencies such as folders and config files already exist or are created appropriately...

# this is static, though you can control where Itko will create tiles/etc and the storage location for the web server root using ${ITKO_ROOT_DIRECTORY}
mkdir -p /itko/ct

# ensure essential directory structure will exist in case volume mounts have created an empty folder.
mkdir -p ${ITKO_ROOT_DIRECTORY}/ct/v1

# create default config if one does not already exist
test -f /itko/ct/config.json || echo '{
  "rootDirectory": "'${ITKO_ROOT_DIRECTORY}'",
  "keyPath":"'${ITKO_KEY_PATH}'",
  "Name":"'${ITKO_LOG_NAME}'",
  "LogID":"'${ITKO_LOG_ID}'",
  "NotAfterStart":"'${NOT_AFTER_START}'",
  "NotAfterLimit":"'${NOT_AFTER_LIMIT}'",
  "MaskSize":'${ITKO_MASK_SIZE}',
  "FlushMs":'${ITKO_FLUSH_MS}'
}' > /itko/ct/config.json

# itko will fix get-sth file contents provided it starts as an empty JSON file, otherwise it will error.
test -s ${ITKO_ROOT_DIRECTORY}/ct/v1/get-sth || echo -n '{}' > ${ITKO_ROOT_DIRECTORY}/ct/v1/get-sth

# generate monitor.json files, refer to:
#  1. https://googlechrome.github.io/CertificateTransparency/log_lists.html
#  2. https://www.gstatic.com/ct/log_list/v3/log_list_schema.json

MONITOR_RFC_JSON='{
  "is_all_logs": false,
  "version": "1.0.0",
  "log_list_timestamp": "'${NOW}'",
  "name": "testing",
  "operators": [
    {
      "name": "testing",
      "email": [
        "test@example.com"
      ],
      "logs": [
        {
          "description": "'${ITKO_LOG_NAME}'",
          "log_id": "'${ITKO_LOG_ID}'",
          "key": "'${ITKO_LOG_PUBLIC_KEY}'",
          "url": "'${ITKO_LOG_MONITORING_URL}'",
          "mmd": 86400,
          "state": {
            "usable": {
              "timestamp": "'${NOW}'"
            }
          },
          "temporal_interval": {
            "start_inclusive": "'${NOT_AFTER_START}'",
            "end_exclusive": "'${NOT_AFTER_LIMIT}'"
          }
        }
      ],
      "tiled_logs": []
    }
  ]
}'

MONITOR_STATIC_JSON='{
  "is_all_logs": false,
  "version": "1.0.0",
  "log_list_timestamp": "'${NOW}'",
  "name": "testing",
  "operators": [
    {
      "name": "testing",
      "email": [
        "test@example.com"
      ],
      "logs": [],
      "tiled_logs": [
        {
          "description": "'${ITKO_LOG_NAME}'",
          "log_id": "'${ITKO_LOG_ID}'",
          "key": "'${ITKO_LOG_PUBLIC_KEY}'",
          "monitoring_url": "'${ITKO_LOG_MONITORING_URL}'",
          "submission_url": "'${ITKO_LOG_SUBMISSION_URL}'",
          "mmd": 60,
          "state": {
            "usable": {
              "timestamp": "'${NOW}'"
            }
          },
          "temporal_interval": {
            "start_inclusive": "'${NOT_AFTER_START}'",
            "end_exclusive": "'${NOT_AFTER_LIMIT}'"
          }
        }
      ]
    }
  ]
}'

MONITOR_COMBINED_JSON='{
  "is_all_logs": false,
  "version": "1.0.0",
  "log_list_timestamp": "'${NOW}'",
  "name": "testing",
  "operators": [
    {
      "name": "testing",
      "email": [
        "test@example.com"
      ],
      "logs": [
        {
          "description": "'${ITKO_LOG_NAME}'",
          "log_id": "'${ITKO_LOG_ID}'",
          "key": "'${ITKO_LOG_PUBLIC_KEY}'",
          "url": "'${ITKO_LOG_MONITORING_URL}'",
          "mmd": 86400,
          "state": {
            "usable": {
              "timestamp": "'${NOW}'"
            }
          },
          "temporal_interval": {
            "start_inclusive": "'${NOT_AFTER_START}'",
            "end_exclusive": "'${NOT_AFTER_LIMIT}'"
          }
        }
      ],
      "tiled_logs": [
        {
          "description": "'${ITKO_LOG_NAME}'",
          "log_id": "'${ITKO_LOG_ID}'",
          "key": "'${ITKO_LOG_PUBLIC_KEY}'",
          "monitoring_url": "'${ITKO_LOG_MONITORING_URL}'",
          "submission_url": "'${ITKO_LOG_SUBMISSION_URL}'",
          "mmd": 60,
          "state": {
            "usable": {
              "timestamp": "'${NOW}'"
            }
          },
          "temporal_interval": {
            "start_inclusive": "'${NOT_AFTER_START}'",
            "end_exclusive": "'${NOT_AFTER_LIMIT}'"
          }
        }
      ]
    }
  ]
}'

# always update the monitor*.json files in case variables changed.
echo "${MONITOR_RFC_JSON}" > ${ITKO_ROOT_DIRECTORY}/monitor-rfc6962.json
echo "${MONITOR_STATIC_JSON}" > ${ITKO_ROOT_DIRECTORY}/monitor-static.json
echo "${MONITOR_COMBINED_JSON}" > ${ITKO_ROOT_DIRECTORY}/monitor-combined.json

# add test to conform to default caddy healthcheck
echo 'OK' > ${ITKO_ROOT_DIRECTORY}/status

# start supervisor which will start everything else...
supervisord --nodaemon --configuration /etc/supervisord.conf

# EOF
