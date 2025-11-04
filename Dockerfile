# Go builder
FROM golang:alpine AS builder

# build the custom certspotter binary
COPY . /tmp/build
WORKDIR /tmp/build
RUN go build -v -o ./itko-submit ./cmd/itko-submit && \
    go build -v -o ./itko-monitor ./cmd/itko-monitor

# Final image
FROM hashicorp/consul:latest

RUN apk add make supervisor && \
  mkdir -p /itko/ct/storage/ct/v1 && \
  adduser -D -s /sbin/nologin -h /itko itko && \
  mv /usr/local/bin/docker-entrypoint.sh /usr/local/bin/consul-entrypoint.sh

WORKDIR /itko

COPY --from=builder --chmod=755 /tmp/build/itko-submit /itko/itko-submit
COPY --from=builder --chmod=755 /tmp/build/itko-monitor /itko/itko-monitor
COPY example/supervisor.d/ /etc/supervisor.d
COPY integration/testdata/ /itko/testdata
COPY example/start-itko-submit.sh /itko/start-itko-submit.sh

USER root:root

EXPOSE 80

COPY itko-entrypoint.sh /usr/local/bin/itko-entrypoint.sh
COPY ./integration/testdata/ /itko/testdata

HEALTHCHECK --interval=5s --timeout=1s --retries=3 --start-period=5s CMD curl -f http://127.0.0.1:${ITKO_MONITOR_LISTEN_PORT:-80}/ct/v1/get-sth | grep '"tree_size":' || exit 1

ENTRYPOINT ["/usr/local/bin/itko-entrypoint.sh"]

# EOF
