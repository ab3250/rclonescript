#!/usr/bin/env bash
# Source this file:  source ./decrypt_snippet.sh
#blob from pwencrypt.sh "AWS_KEY=AAA AWS_SECRET=TGH44"
blob=$(tr -d '[:space:]' <<'EOF'
LS0tLS1CRUdJTiBQR1AgTUVTU0FHRS0tLS0tCgpoRjREYTlycnF5Q0dUZThTQVFk
QUxCV2l5c2RrdGJPbk8wTkROWDNHb1c1ODltWEtkdzVrQ2lrb3gwbXNzbHd3Ck9W
NHRLOEN0RmdoYWNnbU04cTFvWUtnTWJLTjhEaGNqL1pHU0ROMENleGNUeW8reXJO
WndiK0pqU3NUd05qdFkKMUY4QkNRSVE1aDBZS002YUF2Qm1UWXIvNmIydHgzOVZZ
M0owd2lDaUwvbHRxS296bXpGKzBZMVhUN0pRbm04QwpyU3dQV3psWHVHbXlNYno5
MTlUQ0ZZQXJCYVA4RlBQbExEWXRrUXk5WjNLaGxMclJ1T1VRNlkzbjZ2Qi9iL2No
CkFRPT0KPXVOT24KLS0tLS1FTkQgUEdQIE1FU1NBR0UtLS0tLQo=
EOF
)

plain=$(printf '%s' "$blob" | base64 -d | gpg \
  --decrypt \
  --pinentry-mode=ask \
  --no-symkey-cache \
  --quiet \
  --no-greeting)

IFS= read -ra pairs <<< "$plain"
for pair in "${pairs[@]}"; do
  [[ -z $pair ]] && continue
  key=${pair%%=*}
  val=${pair#*=}
  printf -v "$key" '%s' "$val"
  export "$key"  
done

