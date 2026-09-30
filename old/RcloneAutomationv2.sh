#!/bin/bash
#AWSACCESSPLAINBASE:aws.crypt.base/
#AWSACCESSCRYPT:aws.crypt.base
#deep :s3:glacier-deep-archive-backup-ab
#
# Interactive rclone copy launcher.
# Secrets live in the embedded PGP blob (RCLONE_PASSWORD, RCLONE_SALT,
# RCLONE_CONFIG_AWSDEEP_ACCESS_KEY_ID, RCLONE_CONFIG_AWSDEEP_SECRET_ACCESS_KEY).
# They are exported for the rclone process only and wiped on exit.

set -euo pipefail
unset HISTFILE

export GPG_TTY="${GPG_TTY:-$(tty 2>/dev/null || true)}"

SECRET_KEYS=(
  RCLONE_PASSWORD
  RCLONE_SALT
  RCLONE_CONFIG_AWSDEEP_ACCESS_KEY_ID
  RCLONE_CONFIG_AWSDEEP_SECRET_ACCESS_KEY
  RCLONE_S3_ACCESS_KEY_ID
  RCLONE_S3_SECRET_ACCESS_KEY
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  RCLONE_CONFIG_SECRET_PASSWORD
  RCLONE_CONFIG_SECRET_PASSWORD2
)

wipe_secrets() {
  local k
  for k in "${SECRET_KEYS[@]}"; do
    unset "$k" 2>/dev/null || true
  done
  unset plain blob pairs pair key val 2>/dev/null || true
}
trap wipe_secrets EXIT INT TERM

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd gpg
need_cmd base64
need_cmd rclone

# ======================== Get Secrets ===================
blob=$(tr -d '[:space:]' <<'EOF'
LS0tLS1CRUdJTiBQR1AgTUVTU0FHRS0tLS0tCgpoRjREYTlycnF5Q0dUZThTQVFk
QTFJNXA3UXBYbUJDUlJvSXdWZGdDVUsvRFRidllpRWd1Z0d5czNnN01Pa1V3ClVx
aGE4SVZVcFI0RUpRalZMQ1dqWGNnUzFOU21ScHltTjB4SmdlQmw2UDVQSkNhV0px
ZGhnajVPZk8rTFU2dEoKMU1BN0FRa0NFTzZnbEtjcS9KcHBLemJ6ODlrY1Zodk5m
UG45c3IzS1dWQ3Y2VTVMYThLSUFFWjhEUUQrUlZJVApheXlsc3FzV0xNMzlCSFM5
ME5tMmtmdHk5TEdFV1VHK1A2S2l4T2duMmlTSDFqN1V2NlBXSStCdDdvbGkxMmhl
ClNlVlBtQks2WnA3eFNhTlh0clVPUWZUVGxwQUFXSnh0Znk5Y2hFa2VSSTBYNy83
UWVzaHdhUnNGS2w1YnFGb3MKY0NQZjZCZ1lFVml6cTBZQ0lRaWViVWNxTlp6QU1C
Mk1HRStTYmN0L2x3MEFrWnMrVFJ1WktWazZpUlZxeDV3VworeTZYT1lTM0FaWnhk
NjFCWUJlUEJVR3BGUEpnT2J6ZExNbTNHeURIQnJsaDdISEI1Y0ZCdmIya1lXRjFP
Z2ZBCmVMKzdQWGw5dkhxUlVwVmtyUWM9Cj04eFRtCi0tLS0tRU5EIFBHUCBNRVNT
QUdFLS0tLS0K
EOF
)

echo "Decrypting secrets (gpg will prompt for the passphrase)..."
plain=$(printf '%s' "$blob" | base64 -d | gpg \
  --decrypt \
  --pinentry-mode=ask \
  --no-symkey-cache \
  --quiet \
  --no-greeting)

if [[ -z "${plain// }" ]]; then
  echo "gpg decrypt produced no data." >&2
  exit 1
fi

# Accept space- or newline-separated KEY=VALUE pairs. Values must not contain spaces.
while IFS= read -r pair; do
  [[ -z $pair ]] && continue
  key=${pair%%=*}
  val=${pair#*=}
  if [[ ! $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "Ignoring unexpected secret key name: $key" >&2
    continue
  fi
  printf -v "$key" '%s' "$val"
  export "$key"
done < <(printf '%s\n' "$plain" | tr ' ' '\n')

unset plain blob pair key val

for required in \
  RCLONE_CONFIG_AWSDEEP_ACCESS_KEY_ID \
  RCLONE_CONFIG_AWSDEEP_SECRET_ACCESS_KEY
do
  if [[ -z "${!required:-}" ]]; then
    echo "Decrypted blob is missing $required" >&2
    exit 1
  fi
done

# Named remote "awsdeep" (used as awsdeep:bucket/path).
export RCLONE_CONFIG_AWSDEEP_TYPE="s3"
export RCLONE_CONFIG_AWSDEEP_PROVIDER="AWS"
export RCLONE_CONFIG_AWSDEEP_REGION="us-east-1"

# On-the-fly :s3: remotes ignore RCLONE_CONFIG_AWSDEEP_*. Wire the same
# keys the ways rclone actually reads for an unnamed S3 backend.
export RCLONE_S3_ACCESS_KEY_ID="$RCLONE_CONFIG_AWSDEEP_ACCESS_KEY_ID"
export RCLONE_S3_SECRET_ACCESS_KEY="$RCLONE_CONFIG_AWSDEEP_SECRET_ACCESS_KEY"
export AWS_ACCESS_KEY_ID="$RCLONE_CONFIG_AWSDEEP_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$RCLONE_CONFIG_AWSDEEP_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="us-east-1"

# Optional client-side crypt remote named "secret".
# Uncomment and set RCLONE_CONFIG_SECRET_REMOTE to the underlying remote
# (example: awsdeep:glacier-deep-archive-backup-ab) to use secret:path.
# rclone obscure is required; raw passwords are not accepted in env/config.
if [[ -n "${RCLONE_PASSWORD:-}" && -n "${RCLONE_SALT:-}" ]] && command -v rclone >/dev/null; then
  export RCLONE_CONFIG_SECRET_TYPE=crypt
  export RCLONE_CONFIG_SECRET_FILENAME_ENCRYPTION=standard
  export RCLONE_CONFIG_SECRET_DIRECTORY_NAME_ENCRYPTION=true
  export RCLONE_CONFIG_SECRET_PASSWORD="$(rclone obscure "$RCLONE_PASSWORD")"
  export RCLONE_CONFIG_SECRET_PASSWORD2="$(rclone obscure "$RCLONE_SALT")"
  # export RCLONE_CONFIG_SECRET_REMOTE="awsdeep:glacier-deep-archive-backup-ab"
fi

BW="250M"
RATE="1000G"

# Format: "Display Name|source|destination|bucket|storageClass"
# bucket may be an on-the-fly remote (:s3:bucket-name) or a named remote
# prefix (awsdeep:bucket-name). Destination is the path inside that bucket.
presets=(
  "Backup Google Takeout to AWS DEEP Archive|/home/ab/Downloads/dtach/googleTakeout/|googletakeout/|:s3:glacier-deep-archive-backup-ab|DEEP_ARCHIVE"
  "Archive Gentoo25 to AWS Deep|/media/freespace/gentoo25/|gentoo.backup|:s3:glacier-deep-archive-backup-ab|DEEP_ARCHIVE"
  # "Copy Gentoo25 to AWS Encrypted|/mnt/tmp1/gentoo25/|Dimg/Images/gentoo25/gentoo25.100126/|secret:|STANDARD"
)

echo
echo "=== rclone copy – Preset Launcher ==="
echo
echo "Available presets:"
echo

for i in "${!presets[@]}"; do
  name="${presets[$i]%%|*}"
  printf "  %2d) %s\n" $((i+1)) "$name"
done
echo

while true; do
  read -r -p "Enter the number of the preset you want: " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#presets[@]} )); then
    selected="${presets[$((choice-1))]}"
    break
  else
    echo "Invalid choice. Please enter a number between 1 and ${#presets[@]}."
  fi
done

IFS='|' read -r preset_name source destination bucket storageClass <<< "$selected"

echo
echo "→ Selected preset: $preset_name"
echo "  Source:        $source"
echo "  Destination:   $destination"
echo "  Bucket:        $bucket"
echo "  Storage class: $storageClass"
echo

if [[ ! -e "$source" ]]; then
  echo "Source path does not exist: $source" >&2
  exit 1
fi

echo "Do you want a DRY-RUN? (no real changes)"
select dry in "Yes (add --dry-run)" "No (real copy)"; do
  case $REPLY in
    1) dry_run="--dry-run"; break ;;
    2) dry_run=""; break ;;
    *) echo "Invalid choice" ;;
  esac
done
echo

safe_bucket="${bucket#:s3:}"
safe_bucket="${safe_bucket//[:\/]/_}"
logdir="${RCLONE_LOGDIR:-.}"
mkdir -p "$logdir"
logfile="${logdir}/log-aws-${storageClass}-${safe_bucket}-$(date +%F).log"

use_dtach=0
sock=""
if command -v dtach >/dev/null 2>&1; then
  sockdir="${XDG_RUNTIME_DIR:-/tmp}/rclone-dtach"
  mkdir -p "$sockdir"
  sock="${sockdir}/$(date +%F_%H-%M-%S).sock"
  use_dtach=1
else
  echo "dtach not found; running rclone in the foreground."
fi

# copy (not sync): extras already in the destination are left alone.
cmd=()
if (( use_dtach )); then
  cmd+=(dtach -A "$sock")
fi
cmd+=(
  rclone copy "$source" "${bucket}/${destination}"
  --config=/dev/null
  --s3-provider AWS
  --s3-region=us-east-1
  --s3-storage-class "$storageClass"
  --log-file="$logfile"
  --log-level INFO
  --bwlimit "$BW"
  --cutoff-mode SOFT
  --max-transfer "$RATE"
  --progress
  --transfers=1
  --s3-upload-concurrency=16
  --s3-chunk-size=16M
)

[[ -n "$dry_run" ]] && cmd+=("$dry_run")

echo "================ PROPOSED COMMAND ================"
printf '%q ' "${cmd[@]}"
echo
echo "=================================================="
if (( use_dtach )); then
  echo "dtach socket: $sock"
  echo "Reattach later with: dtach -a $(printf '%q' "$sock")"
fi
echo "Log file:     $logfile"
echo

read -r -p "Type 'yes' to run this command (anything else cancels): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Cancelled."
  exit 0
fi

echo
echo "Starting..."
set +e
"${cmd[@]}"
rc=$?
set -e
exit "$rc"
