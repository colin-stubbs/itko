#!/bin/sh

# ensure consul is started before we try to blat the config into it...
echo -n "### Waiting for Consul to start..."
while ! curl -s http://127.0.0.1:8500/v1/status/leader >/dev/null 2>&1; do
  sleep 1
  echo -n "."
done
echo "OK!"

# setup KV in consul (but give it a little more time to start so it can lose anything...)
sleep 4
echo "### Loading Itko config as KV /itko/config..."
curl ${CURL_EXTRA_ARGS} -X PUT -H 'Content-Type: application/json' -d "@/itko/ct/config.json" "http://127.0.0.1:8500/v1/kv/${ITKO_KV_PATH}/config" 1>/dev/null 2>&1

# start itko-submit
echo "### Starting itko-submit..."
/itko/itko-submit -getentries_metrics -kv-path "${ITKO_KV_PATH}" -listen-address "${ITKO_SUBMIT_LISTEN_ADDRESS}:${ITKO_SUBMIT_LISTEN_PORT}"

# EOF

