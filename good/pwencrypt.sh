#!/usr/bin/env bash
# Encrypt space-separated KEY=VALUE secrets to the YubiKey key.
# Prints one base64 line.
#
#   ./pwencrypt.sh ACCESS_KEY_ID=AKI... SECRET_ACCESS_KEY=wJal... OTHER=foo
#   echo 'ACCESS_KEY_ID=AKI... SECRET_ACCESS_KEY=wJal...' | ./pwencrypt.sh
#
# Values must not contain spaces.

recipient="${GPG_RECIPIENT:-6BDAEBAB20864DEF}"

if [[ $# -gt 0 ]]; then
  pairs=("$@")
else
  # stdin: collapse newlines/tabs to spaces
  read -r -a pairs <<< "$(tr '\n\t' '  ')"
fi

plain=""
for pair in "${pairs[@]}"; do
  [[ -z $pair ]] && continue
  [[ $pair == *=* ]] || { echo "expected KEY=VALUE: $pair" >&2; exit 1; }
  key=${pair%%=*}
  [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "bad name: $key" >&2; exit 1; }
  plain+="${plain:+ }$pair"
done

[[ -n $plain ]] || { echo "no input" >&2; exit 1; }

#printf '%s' "$plain" \
#  | gpg --encrypt --armor --quiet --no-greeting -r "$recipient" \
#  | base64 --wrap 0
#echo


printf '%s' "$plain" \
  | gpg --encrypt --armor --quiet --no-greeting -r "$recipient" \
  | base64 --wrap 0 | fold -w 64
echo


#blob=$(tr -d '[:space:]' <<'EOF'
#LS0tLS1CRUdJTiBQR1AgTUVTU0FHRS0tLS0tCk...
#...rest of ONE-LINE base64 from your encrypt command...
#EOF
#)

#plain=$(printf '%s' "$blob" | base64 -d | gpg \
#  --decrypt --pinentry-mode=loopback --no-symkey-cache \
#  --quiet --no-greeting)