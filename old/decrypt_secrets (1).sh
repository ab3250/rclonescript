#!/usr/bin/env bash
# decrypt_secrets.sh
# Decrypt a base64-wrapped GPG-symmetric payload produced by:
#
#   echo $(echo "KEY=value|KEY2=value2" | gpg \
#     --symmetric --pinentry-mode=loopback --no-symkey-cache \
#     --cipher-algo aes256 --digest-algo sha256 \
#     --s2k-digest-algo SHA512 --s2k-cipher-algo AES256 \
#     --s2k-mode 3 --s2k-count 65011712 \
#     --cert-digest-algo sha256 --compress-algo none -z 0 \
#     --quiet --no-greeting --armor | base64 --wrap 0)
#
# Then split KEY=VALUE pairs on '|' and export them as shell variables.
#
# Usage:
#   source ./decrypt_secrets.sh '<base64-encrypted-string>'
#   source ./decrypt_secrets.sh -f encrypted.txt
#   ENCRYPTED='...' source ./decrypt_secrets.sh
#
# Passphrase:
#   - Interactive prompt (default)
#   - GPG_PASSPHRASE env var
#   - --passphrase-file FILE
#   - --passphrase-fd N
#
# MUST be sourced (not executed) if you want the variables in the current shell:
#   source ./decrypt_secrets.sh '...'
# Running it as a program only prints exports.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  source decrypt_secrets.sh [options] [ENCRYPTED_STRING]
  source decrypt_secrets.sh [options] -f FILE

Options:
  -f, --file FILE           Read encrypted string from FILE
  -p, --passphrase-file F   Read GPG passphrase from file F
      --passphrase-fd N     Read GPG passphrase from FD N
  -q, --quiet               Suppress status messages
  -n, --dry-run             Decrypt and print KEY=VALUE pairs, do not export
  -h, --help                Show this help

The decrypted payload is a pipe-separated list of KEY=VALUE items, e.g.:
  RCLONE_CONFIG_SECRET_TYPE=crypt|RCLONE_CONFIG_MYSECRET_PASSWORD=sedd

Any number of items is supported. Keys must match [A-Za-z_][A-Za-z0-9_]*.
Values may contain '=', spaces, and most characters except '|'.
To include a literal '|' in a value, encode it as %7C in the plaintext
before encryption; it will be decoded after decrypt.
EOF
}

log() {
  if [[ "${QUIET:-0}" != "1" ]]; then
    printf '%s\n' "$*" >&2
  fi
}

die() {
  printf 'error: %s\n' "$*" >&2
  return 1
}

ENCRYPTED=""
PASSPHRASE_FILE=""
PASSPHRASE_FD=""
QUIET=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      return 0 2>/dev/null || exit 0
      ;;
    -f|--file)
      [[ $# -ge 2 ]] || die "missing argument for $1"
      ENCRYPTED="$(<"$2")"
      shift 2
      ;;
    -p|--passphrase-file)
      [[ $# -ge 2 ]] || die "missing argument for $1"
      PASSPHRASE_FILE="$2"
      shift 2
      ;;
    --passphrase-fd)
      [[ $# -ge 2 ]] || die "missing argument for $1"
      PASSPHRASE_FD="$2"
      shift 2
      ;;
    -q|--quiet)
      QUIET=1
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      if [[ -n "$ENCRYPTED" ]]; then
        die "encrypted string already set"
      fi
      ENCRYPTED="$1"
      shift
      ;;
  esac
done

if [[ -z "$ENCRYPTED" && -n "${ENCRYPTED_SECRET:-}" ]]; then
  ENCRYPTED="$ENCRYPTED_SECRET"
fi

# strip whitespace / newlines that often sneak into copied blobs
ENCRYPTED="${ENCRYPTED//[[:space:]]/}"

[[ -n "$ENCRYPTED" ]] || die "no encrypted string provided (arg, -f FILE, or ENCRYPTED_SECRET)"

command -v gpg >/dev/null || die "gpg not found"
command -v base64 >/dev/null || die "base64 not found"

gpg_args=(
  --decrypt
  --pinentry-mode=loopback
  --no-symkey-cache
  --quiet
  --no-greeting
  --batch
)

if [[ -n "$PASSPHRASE_FILE" ]]; then
  gpg_args+=(--passphrase-file "$PASSPHRASE_FILE")
elif [[ -n "$PASSPHRASE_FD" ]]; then
  gpg_args+=(--passphrase-fd "$PASSPHRASE_FD")
elif [[ -n "${GPG_PASSPHRASE:-}" ]]; then
  gpg_args+=(--passphrase "$GPG_PASSPHRASE")
else
  # interactive: drop --batch so pinentry/loopback can prompt
  gpg_args=(
    --decrypt
    --pinentry-mode=loopback
    --no-symkey-cache
    --quiet
    --no-greeting
  )
fi

PLAINTEXT=""
if ! PLAINTEXT="$(printf '%s' "$ENCRYPTED" | base64 --decode 2>/dev/null | gpg "${gpg_args[@]}" 2>/dev/null)"; then
  die "decryption failed (bad passphrase, corrupt blob, or missing gpg)"
fi

# trim a single trailing newline that echo often adds during encryption
PLAINTEXT="${PLAINTEXT%$'\n'}"

[[ -n "$PLAINTEXT" ]] || die "decrypted payload is empty"

# Split on '|' without globbing
IFS='|' read -r -a _pairs <<< "$PLAINTEXT"

exported=()
for pair in "${_pairs[@]}"; do
  [[ -n "$pair" ]] || continue
  if [[ "$pair" != *=* ]]; then
    die "malformed item (expected KEY=VALUE): $pair"
  fi
  key="${pair%%=*}"
  value="${pair#*=}"
  # decode optional %7C used as an escape for literal pipes
  value="${value//%7C/|}"
  value="${value//%7c/|}"

  if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    die "invalid variable name: $key"
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s=%s\n' "$key" "$value"
  else
    # export into current shell when sourced
    printf -v "$key" '%s' "$value"
    export "$key"
    exported+=("$key")
  fi
done

if [[ "$DRY_RUN" != "1" ]]; then
  log "exported ${#exported[@]} variable(s): ${exported[*]}"
fi
