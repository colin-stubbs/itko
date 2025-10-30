#!/bin/sh

# itko-entrypoint.sh

# ensure all variables are set with sane defaults.
# Consul configuration, refer to /usr/local/bin/consul-entrypoint.sh or https://hub.docker.com/_/consul/
CONSUL_BIND_ADDRESS=${CONSUL_BIND_ADDRESS:-127.0.0.1}
CONSUL_BIND_INTERFACE=${CONSUL_BIND_INTERFACE:-lo}
CONSUL_CLIENT_ADDRESS=${CONSUL_CLIENT_ADDRESS:-127.0.0.1}
CONSUL_CLIENT_INTERFACE=${CONSUL_CLIENT_INTERFACE:-lo}
CONSUL_LOCAL_CONFIG=${CONSUL_LOCAL_CONFIG:-{"datacenter":"dev","server":true,"enable_debug":false}}

# set to true to load test certs from testdata/
LOAD_TEST_DATA=${LOAD_TEST_DATA:-false}
# set to 1+ to auto-generate certificates, NOTE: this is dependent upon LOAD_TEST_DATA being true and will not occur if LOAD_TEST_DATA is false.
GEN_TEST_CERTS=${GEN_TEST_CERTS:-}

# Itko configuration, refer to the remainder of this script to understand how these are used.
ITKO_KV_PATH=${ITKO_KV_PATH:-itko}
ITKO_ROOT_DIRECTORY=${ITKO_ROOT_DIRECTORY:-/itko/ct/storage}
ITKO_KEY_PATH=${ITKO_KEY_PATH:-/itko/testdata/ct-http-server.privkey.plaintext.pem}
ITKO_LOG_NAME=${ITKO_LOG_NAME:-testlog}
ITKO_LOG_ID=${ITKO_LOG_ID:-lrviNpCI/wLGL5VTfK25b8cOdbP0YA7tGoQak5jST9o=}
ITKO_LOG_PUBLIC_KEY=${ITKO_LOG_PUBLIC_KEY:-MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEB/hRr6qMVoOQMbeA49Ya9y82BnHs3Tu+fjZvDRwcYAt/9Z//5SRJNFbySxBfvwgf+Q7PNbWKioswClS3vx1NuQ==}
ITKO_LOG_SUBMISSION_URL=${ITKO_LOG_SUBMISSION_URL:-http://itko/}
ITKO_LOG_MONITORING_URL=${ITKO_LOG_MONITORING_URL:-http://itko/}
ITKO_MASK_SIZE=${ITKO_MASK_SIZE:-5}
ITKO_FLUSH_MS=${ITKO_FLUSH_MS:-50}
ITKO_SUBMIT_LISTEN_ADDRESS=${ITKO_SUBMIT_LISTEN_ADDRESS:-127.0.0.1}
ITKO_SUBMIT_LISTEN_PORT=${ITKO_SUBMIT_LISTEN_PORT:-3030}
ITKO_MONITOR_LISTEN_ADDRESS=${ITKO_MONITOR_LISTEN_ADDRESS:-127.0.0.1}
ITKO_MONITOR_LISTEN_PORT=${ITKO_MONITOR_LISTEN_PORT:-3031}

# Caddy configuration, refer to the remainder of this script to understand how these are used.
CADDY_LISTEN_PORT=${CADDY_LISTEN_PORT:-80}
CADDY_LISTEN_ADDRESS=${CADDY_LISTEN_ADDRESS:-0.0.0.0}
CADDY_CONFIG_FILE=${CADDY_CONFIG_FILE:-/itko/ct/Caddyfile}
CADDY_CONFIG_ADAPTER=${CADDY_CONFIG_ADAPTER:-caddyfile}

# control curl's behaviour, retry up to 10 times with a 1 second delay between retries.
CURL_EXTRA_ARGS="--retry-connrefused --retry-all-errors --retry-delay 1 --retry 10"

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
test -f ${ITKO_ROOT_DIRECTORY}/ct/v1/get-sth || echo -n '{}' > ${ITKO_ROOT_DIRECTORY}/ct/v1/get-sth

if [ ${LOAD_TEST_DATA} = "true" ]; then
  cd /itko/testdata
  # ensure the intermediate cert and everthing else is created

  # generate additional test certs if requested
  if [ "${GEN_TEST_CERTS}x" != "x" ] && [ ${GEN_TEST_CERTS} -ge 1 ]; then
    echo "### Creating ${GEN_TEST_CERTS} additional test leaf certificates..."
    # we use the generated sub-folder that can be a volume mounted store to speed up the process by avoiding re-generating keys and certificates all of the time.
    mkdir -p /itko/testdata/generated

    # Create additional fake test root CA and intermediate CA as previously generated EC keys/etc seem to be b0rked in more recent OpenSSL versions?!?
    test -f /itko/testdata/generated/test-ca.privkey.pem || openssl ecparam -genkey -name prime256v1 -noout -out /itko/testdata/generated/test-ca.privkey.pem 1>/dev/null 2>&1
    test -f /itko/testdata/generated/test-ca.cert || openssl req -new -x509 -config /itko/testdata/fake-ca.cfg -set_serial 0x0406cafe -days 3650 -extensions v3_ca -inform pem -key /itko/testdata/generated/test-ca.privkey.pem -out /itko/testdata/generated/test-ca.cert 1>/dev/null 2>&1
    test -f /itko/testdata/generated/test-int-ca.privkey.pem || openssl ecparam -genkey -name prime256v1 -noout -out /itko/testdata/generated/test-int-ca.privkey.pem 1>/dev/null 2>&1
    test -f /itko/testdata/generated/test-int-ca.csr.pem || openssl req -new -sha256 -config /itko/testdata/int-ca.cfg -key /itko/testdata/generated/test-int-ca.privkey.pem -out /itko/testdata/generated/test-int-ca.csr.pem 1>/dev/null 2>&1
    test -f /itko/testdata/generated/test-int-ca.cert || openssl x509 -req -in /itko/testdata/generated/test-int-ca.csr.pem -sha256 -extfile /itko/testdata/fake-ca.cfg -extensions v3_int_ca -CA /itko/testdata/generated/test-ca.cert -CAkey /itko/testdata/generated/test-ca.privkey.pem -set_serial 0x53535353 -days 3600 -out /itko/testdata/generated/test-int-ca.cert 1>/dev/null 2>&1

    for n in `seq 1 ${GEN_TEST_CERTS}`; do
      if [ ! -f /itko/testdata/generated/test-subleaf-${n}.cert ]; then
        echo "### Creating test subleaf ${n} certificate..."
        openssl ecparam -genkey -name prime256v1 -noout -out /itko/testdata/generated/test-subleaf-${n}.privkey.pem 1>/dev/null 2>&1
        openssl req -new -sha256 -key /itko/testdata/generated/test-subleaf-${n}.privkey.pem -subj "/C=AU/ST=Queensland/O=Good Roots Work/OU=Eng/CN=test-subleaf-${n}.example.com" -out /itko/testdata/generated/test-subleaf-${n}.csr.pem 1>/dev/null 2>&1
        openssl x509 -req -in /itko/testdata/generated/test-subleaf-${n}.csr.pem -sha256 -extfile /itko/testdata/int-ca.cfg -extensions v3_user -CA /itko/testdata/generated/test-int-ca.cert -CAkey /itko/testdata/generated/test-int-ca.privkey.pem -set_serial 0xdeadbeef -days 2600 -out /itko/testdata/generated/test-subleaf-${n}.cert 1>/dev/null 2>&1
      fi
    done
  fi

  echo "### Loading test data trusted roots..."
  # add all of our fake test CA's as trusted roots.
  test -f ${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots || cat fake-ca*.cert generated/test-ca.cert | tr  -d '\n' | sed -E -e 's/^/{"certificates":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' > ${ITKO_ROOT_DIRECTORY}/ct/v1/get-roots
  cd /itko
fi

# start itko-submit
nohup /itko/itko-submit -getentries_metrics -kv-path ${ITKO_KV_PATH} -listen-address ${ITKO_SUBMIT_LISTEN_ADDRESS}:${ITKO_SUBMIT_LISTEN_PORT} 1>/var/log/itko-submit_stdout.log 2>/var/log/itko-submit_stderr.log &

echo -n "### Waiting for itko-submit to start and respond to HTTP requests..."
while ! curl -s http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ >/dev/null 2>&1; do
  sleep 1
  echo -n "."
done
echo "OK!"

echo "### itko-submit started and responding to HTTP requests..."

if [ ${LOAD_TEST_DATA} = "true" ]; then
  echo "### Loading test data..."
  # add cert to log
  cat /itko/testdata/subleaf.chain | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > /itko/testdata/subleaf.chain.json
  curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d '@/itko/testdata/subleaf.chain.json' "http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1/add-chain" 1>/dev/null 2>&1

  # add pre-cert to log
  cat /itko/testdata/subleaf-pre.chain | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > /itko/testdata/subleaf-pre.chain.json
  curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d '@/itko/testdata/subleaf-pre.chain.json' "http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1/add-pre-chain" 1>/dev/null 2>&1

  # log all available leaf certs in testdata directory
  for i in /itko/testdata/leaf*.chain ; do
    echo "### Adding leaf cert ${i} to log..."
    test -f ${i} && cat ${i} | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > ${i}.json
    test -s ${i}.json && curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d "@${i}.json" "http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1/add-chain" 1>/dev/null 2>&1
  done

  # generate additional test certs if requested
  if [ "${GEN_TEST_CERTS}x" != "x" ] && [ ${GEN_TEST_CERTS} -ge 1 ]; then
    echo "### Adding ${GEN_TEST_CERTS} additional test leaf certificates..."

    for n in `seq 1 ${GEN_TEST_CERTS}`; do
      if [ ! -f /itko/testdata/generated/test-subleaf-${n}-chain.json ]; then
        echo "### Creating test subleaf ${n} certificate chain..."
        cat /itko/testdata/generated/test-subleaf-${n}.cert /itko/testdata/generated/test-int-ca.cert /itko/testdata/generated/test-ca.cert | tr  -d '\n' | sed -E -e 's/^/{"chain":[/' -e 's/$/]}/' -e 's/-+BEGIN\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE-+/"/g' -e 's/-+END\sCERTIFICATE/",/g' | jq > /itko/testdata/generated/test-subleaf-${n}-chain.json
      fi
      echo "### Adding test subleaf ${n} certificate chain..."
      test -s /itko/testdata/generated/test-subleaf-${n}-chain.json && curl ${CURL_EXTRA_ARGS} -H 'Content-Type: application/json' -d "@/itko/testdata/generated/test-subleaf-${n}-chain.json" "http://127.0.0.1:${ITKO_SUBMIT_LISTEN_PORT}/ct/v1/add-chain" 1>/dev/null 2>&1
    done
  fi
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
                output file /var/log/caddy_access.log
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
}" > ${CADDY_CONFIG_FILE} && caddy fmt --overwrite --config ${CADDY_CONFIG_FILE}

caddy run --adapter ${CADDY_CONFIG_ADAPTER} --config ${CADDY_CONFIG_FILE} --watch

killall -9 itko-submit itko-monitor consul 2>/dev/null || true

# EOF
