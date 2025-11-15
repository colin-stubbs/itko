#!/bin/bash
docker buildx build --platform linux/amd64,linux/arm64 --tag colinstubbs/itko:latest --push .
# EOF

