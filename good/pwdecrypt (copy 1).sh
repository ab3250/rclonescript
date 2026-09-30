#!/usr/bin/env bash
#######################################################
## Source this file:  source ./pwdecrypt.sh
## Sets KEY=VALUE from a space-separated encrypted blob.
#######################################################
blob=$(tr -d '[:space:]' <<'EOF'
LS0tLS1CRUdJTiBQR1AgTUVTU0FHRS0tLS0tCgpqQTBFQ1FNS2QyZVVjKzAvN1lq
LzBuVUJ6N3BPL3I4VGE2WGFkYnUrZE5mOVBGa1NLR294VHMzazMwaVBXVEVkCnFu
ek1LMjNxV3NLNFVucEI3TVAvOGpNQzRwNG1rZWpOMjRpdGs5b1hqY3BjQWtYMzV5
UzMxQWNrb2t2a0JMM2kKLytsT1h5KzRKRkpEUWEvdkh3Zzg3V21RK0FubXNqT3E4
QVdiYmJqYll3M1FUV2IwbFEwPQo9N09pbAotLS0tLUVORCBQR1AgTUVTU0FHRS0t
LS0tCg==
EOF
)

[[ -n ${GPG_TTY:-} ]] || export GPG_TTY=$(tty)

_tmp=$(mktemp)
trap 'rm -f "$_tmp"' RETURN
printf '%s' "$blob" | base64 -d > "$_tmp"

plain=$(gpg --decrypt --pinentry-mode ask --quiet --no-greeting "$_tmp") || return 1

read -r -a pairs <<< "$plain"
for pair in "${pairs[@]}"; do
  [[ -z $pair ]] && continue
  key=${pair%%=*}
  val=${pair#*=}
  printf -v "$key" '%s' "$val"
done
