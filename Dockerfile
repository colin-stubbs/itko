# Go builder
FROM golang:alpine AS builder

# build the custom certspotter binary
COPY . /tmp/build
WORKDIR /tmp/build
RUN go build -v -o ./itko-submit ./cmd/itko-submit && \
    go build -v -o ./itko-monitor ./cmd/itko-monitor

# Final image
FROM hashicorp/consul:latest

RUN apk add make caddy && \
  mkdir -p /itko/ct/storage/ct/v1 && \
  adduser -D -s /sbin/nologin -h /itko itko && \
  mv /usr/local/bin/docker-entrypoint.sh /usr/local/bin/consul-entrypoint.sh

WORKDIR /itko

COPY --from=builder --chmod=755 /tmp/build/itko-submit /itko/itko-submit
COPY --from=builder --chmod=755 /tmp/build/itko-monitor /itko/itko-monitor

USER root:root

EXPOSE 80

COPY itko-entrypoint.sh /usr/local/bin/itko-entrypoint.sh
COPY ./integration/testdata/ /itko/testdata

ENTRYPOINT ["/usr/local/bin/itko-entrypoint.sh"]

# EOF
