#!/bin/bash

set -e

eval "$(jq -r '@sh "PRIVATE_KEY=\(.private_key)"')"

KID=$(echo -n "$PRIVATE_KEY" | openssl rsa -pubout -outform DER 2>/dev/null | openssl dgst -sha256 -binary | openssl enc -base64 | tr '+/' '-_' | tr -d '=' )

jq -n --arg kid "$KID" '{"kid":$kid}'