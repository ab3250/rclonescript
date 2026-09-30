#!/usr/bin/env bash
# Source this file:  source ./decrypt_snippet.sh

blob='PASTE_BASE64_ENCRYPTED_STRING_HERE'

plain=$(printf '%s' "$blob" | base64 -d | gpg \
  --decrypt \
  --pinentry-mode=loopback \
  --no-symkey-cache \
  --quiet \
  --no-greeting)

IFS='|' read -ra pairs <<< "$plain"
for pair in "${pairs[@]}"; do
  [[ -z $pair ]] && continue
  key=${pair%%=*}
  val=${pair#*=}
  printf -v "$key" '%s' "$val"
  export "$key"
done
