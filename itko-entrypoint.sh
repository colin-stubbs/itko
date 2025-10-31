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
export ITKO_LOG_SUBMISSION_URL=${ITKO_LOG_SUBMISSION_URL:-http://itko/}
export ITKO_LOG_MONITORING_URL=${ITKO_LOG_MONITORING_URL:-http://itko/}
export ITKO_MASK_SIZE=${ITKO_MASK_SIZE:-5}
export ITKO_FLUSH_MS=${ITKO_FLUSH_MS:-50}
export ITKO_SUBMIT_LISTEN_ADDRESS=${ITKO_SUBMIT_LISTEN_ADDRESS:-127.0.0.1}
export ITKO_SUBMIT_LISTEN_PORT=${ITKO_SUBMIT_LISTEN_PORT:-3030}
export ITKO_MONITOR_LISTEN_ADDRESS=${ITKO_MONITOR_LISTEN_ADDRESS:-127.0.0.1}
export ITKO_MONITOR_LISTEN_PORT=${ITKO_MONITOR_LISTEN_PORT:-3031}

# Caddy configuration, refer to the remainder of this script to understand how these are used.
export CADDY_LISTEN_PORT=${CADDY_LISTEN_PORT:-80}
export CADDY_LISTEN_ADDRESS=${CADDY_LISTEN_ADDRESS:-0.0.0.0}
export CADDY_CONFIG_FILE=${CADDY_CONFIG_FILE:-/itko/ct/Caddyfile}
export CADDY_CONFIG_ADAPTER=${CADDY_CONFIG_ADAPTER:-caddyfile}

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

# ensure essential directory structure will exist in case volume mounts have created an empty folder.
mkdir -p ${ITKO_ROOT_DIRECTORY}/ct/v1

# start consul because Itko depends upon it. Refer to /usr/local/bin/consul-entrypoint.sh or https://hub.docker.com/_/consul/ for more details.
nohup /usr/local/bin/consul-entrypoint.sh consul agent -server -bootstrap-expect=1 -data-dir=/consul/data 1>/var/log/consul_stdout.log 2>/var/log/consul_stderr.log &

# The current date/time in simple UTC zoned RFC3339 format, used in our generated monitor.json files if we're auto-generating them.
NOW=`date -u -Iseconds | sed -r 's/\+00:00/Z/'`
# Used in our generated monitor.json files if we're auto-generating them, e.g. a long time ago in a galaxy far, far away...
NOT_AFTER_START="2000-01-01T00:00:00Z"
# Used in our generated monitor.json files if we're auto-generating them, e.g. now + years in simple UTC zoned RFC3339 format.
NOT_AFTER_LIMIT="`date -d \"$(($(date +%Y)+10))-$(date +%m)-$(date +%d)\" -I`T00:00:00Z"

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

# ensure consul is started before we try to blat the config into it...
echo -n "### Waiting for Consul to start..."
while ! curl -s http://127.0.0.1:8500/v1/status/leader >/dev/null 2>&1; do
  sleep 1
  echo -n "."
done
echo "OK!"
echo "### Consul started, loading Itko config as KV /itko/config..."

# setup KV in consul (but give it a little more time to start so it can lose anything...)
sleep 4
curl ${CURL_EXTRA_ARGS} -X PUT -H 'Content-Type: application/json' -d "@/itko/ct/config.json" "http://127.0.0.1:8500/v1/kv/${ITKO_KV_PATH}/config" 1>/dev/null 2>&1

# itko will fix get-sth file contents provided it starts as an empty JSON file
test -s ${ITKO_ROOT_DIRECTORY}/ct/v1/get-sth || echo -n '{}' > ${ITKO_ROOT_DIRECTORY}/ct/v1/get-sth

# run generate script to create extra test certs if it exists
test -x /itko/testdata/generated/generate.sh && /itko/testdata/generated/generate.sh
test -x /itko/testdata/add_roots.sh && /itko/testdata/add_roots.sh

if [ ${LOAD_TEST_DATA} = "true" ]; then
  echo "### Loading test data trusted roots..."
  # add all of our fake test CA's as trusted roots. This needs to happen before itko-submit starts.
  test -f ${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots || cat /itko/testdata/fake-ca*.cert /itko/testdata/generated/test-ca.cert 2>/dev/nll | tr  -d '\n' | sed -E -e 's/^/{"certificates":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' > ${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots
fi

# start itko-submit
nohup /itko/itko-submit -getentries_metrics -kv-path "${ITKO_KV_PATH}" -listen-address "${ITKO_SUBMIT_LISTEN_ADDRESS}:${ITKO_SUBMIT_LISTEN_PORT}" 1>/var/log/itko-submit_stdout.log 2>/var/log/itko-submit_stderr.log &

echo -n "### Waiting for itko-submit to start and respond to HTTP requests..."
while ! curl -s http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ >/dev/null 2>&1; do
  sleep 1
  echo -n "."
done
echo "OK!"

echo "### itko-submit started and responding to HTTP requests..."

if [ ${LOAD_TEST_DATA} = "true" ]; then
  echo "### Loading test data..."
  test -x /itko/testdata/add_leaves.sh && /itko/testdata/add_leaves.sh
fi

# start itko-monitor
nohup /itko/itko-monitor -listen-address ${ITKO_MONITOR_LISTEN_ADDRESS}:${ITKO_MONITOR_LISTEN_PORT} -mask-size ${ITKO_MASK_SIZE} -store-directory ${ITKO_ROOT_DIRECTORY} 1>/var/log/itko-monitor_stdout.log 2>/var/log/itko-monitor_stderr.log &

echo -n "### Waiting for itko-monitor to start and get-sth to be available..."
while ! curl -s http://127.0.0.1:${ITKO_MONITOR_LISTEN_PORT}/ct/v1/get-sth >/dev/null 2>&1; do
  sleep 1
  echo -n "."
done
echo "OK!"

echo "### itko-monitor started and responding to HTTP requests..."
echo "### /ct/v1/get-sth"
curl ${CURL_EXTRA_ARGS} "http://127.0.0.1:${ITKO_MONITOR_LISTEN_PORT}/ct/v1/get-sth" | jq

if [ "${DEBUG}x" == "truex" ]; then
  echo "### Debug mode enabled, dumping roots and up to 512 entries..."
  echo "### /ct/v1/get-roots"
  curl ${CURL_EXTRA_ARGS} "http://127.0.0.1:${ITKO_MONITOR_LISTEN_PORT}/ct/v1/get-roots" | jq
  echo "### /ct/v1/get-entries?start=0&end=512"
  curl ${CURL_EXTRA_ARGS} "http://127.0.0.1:${ITKO_MONITOR_LISTEN_PORT}/ct/v1/get-entries?start=0&end=512" | jq
fi

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

test -f ${ITKO_ROOT_DIRECTORY}/monitor-rfc6962.json || echo "${MONITOR_RFC_JSON}" > ${ITKO_ROOT_DIRECTORY}/monitor-rfc6962.json
test -f ${ITKO_ROOT_DIRECTORY}/monitor-static.json || echo "${MONITOR_STATIC_JSON}" > ${ITKO_ROOT_DIRECTORY}/monitor-static.json
test -f ${ITKO_ROOT_DIRECTORY}/monitor-combined.json || echo "${MONITOR_COMBINED_JSON}" > ${ITKO_ROOT_DIRECTORY}/monitor-combined.json

test -f ${CADDY_CONFIG_FILE} || echo "{
  log default {
    output file /var/log/caddy.log
    format json
  }
  auto_https off

  servers :${CADDY_LISTEN_PORT} {
    name http
  }
  default_bind ${CADDY_LISTEN_ADDRESS}
}

:${CADDY_LISTEN_PORT} {
  @blocked {
    path /int/*
  }
  handle @blocked {
    respond \"Access denied\" 403
  }
  reverse_proxy /ct/v1/add-* http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}
  reverse_proxy /ct/v1/get-* http://127.0.0.1:${ITKO_MONITOR_LISTEN_PORT}
  route /monitor-*.json {
    header Content-Type application/json
  }
  root * ${ITKO_ROOT_DIRECTORY}
  file_server
  log {
    output file /var/log/access.log {
      roll_size 10mb
      roll_keep 5
      roll_keep_for 1h
    }
  }
}" > ${CADDY_CONFIG_FILE} && caddy fmt --overwrite --config ${CADDY_CONFIG_FILE}

caddy run --adapter ${CADDY_CONFIG_ADAPTER} --config ${CADDY_CONFIG_FILE} --watch

killall -9 itko-submit itko-monitor consul 2>/dev/null || true

# EOF
