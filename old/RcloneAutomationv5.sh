#!/bin/bash
#AWSACCESSPLAINBASE:aws.crypt.base/
#AWSACCESSCRYPT:aws.crypt.base
#deep :s3:glacier-deep-archive-backup-ab
#
# Interactive rclone copy launcher.
# Secrets live in the embedded PGP blob (RCLONE_PASSWORD, RCLONE_SALT,
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY).
# They are exported for the rclone process only and wiped on exit.

set -euo pipefail
unset HISTFILE 

export GPG_TTY="${GPG_TTY:-$(tty 2>/dev/null || true)}"

SECRET_KEYS=(
  RCLONE_PASSWORD
  RCLONE_SALT
  RCLONE_S3_ACCESS_KEY_ID
  RCLONE_S3_SECRET_ACCESS_KEY
  #RCLONE_CONFIG_DEEP_ACCESS_KEY_ID
  #RCLONE_CONFIG_DEEP_SECRET_ACCESS_KEY
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  CLONE_CONFIG_SECRET_PASSWORD
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
QVdvVXdXakpYYmlRL2pBcTRsbCtqVllQeUUrTExROEN0ZnBwcFpiT2Z1RVV3ClNI
L09xUE1hdXp2c2tRSkpMTFlzZ2t3MDJYb0FldFllQXZVMGd5QkN5WmNsOVNhNkxU
bmZ4WWdHUlRPL2dsSSsKMU1Bd0FRa0NFTXVKQklhTXRmR1RXSnpyZjZlUmp5c3ZE
NHAvaE05UGkvRDBUaHlBZE9NSituaGtZZ3pzaE0rQQpHUzVPK0llMVZrNWk0VUJO
THU2RGNPV1FwTWZpSEQ5VExzWVhTNFVxS204SU5MaFp5MnZUY3h5T1YrYk5SdGgr
CkFmbW5mVVZ4OTVncmVXQTduVHBMdEdWN3EyMG10aHZuVUJXZDhNSlN6dU5jcG1r
RFBDOWd5OEpsdVVyYWFXY24KWkFOa21mSmk1OWhSbExoSVhNaDZPVFlCWTRuOVhn
VE1CdXNGdjdZc2twWHB4UzZWY3BDSGloZytNSUVOUlBUcApwRDIxeUM5YWZkNmN4
QmsydWc2K0hxOUxGZTJ4NC9rU2NWRHBRZGd1UEF3aXNYeWQ2MklvOXMvZUpJZjZH
NGJmCkJrSzMKPXpMcUwKLS0tLS1FTkQgUEdQIE1FU1NBR0UtLS0tLQo=
EOF
)

echo "Decrypting secrets (gpg will prompt for the passphrase)..."
plain=$(printf '%s' "$blob" | base64 -d | gpg \
  --decrypt \
  --pinentry-mode=loopback \
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

for required in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
  if [[ -z "${!required:-}" ]]; then
    echo "Decrypted blob is missing $required" >&2
    exit 1
  fi
done

unset plain blob pair key val

# Named remote "S3" (used as S3:bucket/path).
#============== RCLONE GLOBAL =================
export RCLONE_CONFIG=/dev/null
export RCLONE_MAX_TRANSFER=1000G
export RCLONE_BWLIMIT=250M
export RCLONE_CUTOFF_MODE=SOFT
export RCLONE_TRANSFERS=1
export RCLONE_LOG_LEVEL=INFO
export RCLONE_LOG_FILE="log-$(date "+%F-%T")"
export RCLONE_S3_REGION=us-east-1
export RCLONE_S3_UPLOAD_CONCURRENCY=16
export RCLONE_S3_CHUNK_SIZE=16M
export AWS_ACCESS_KEY_ID=your_aws_access_key_id
export AWS_SECRET_ACCESS_KEY=your_aws_secret_access_key
export AWS_DEFAULT_REGION=us-east-1
#============== Amazon S3 ================= 
export RCLONE_CONFIG_DEEP_TYPE=s3
export RCLONE_CONFIG_DEEP_PROVIDER=AWS
export RCLONE_CONFIG_DEEP_ACCESS_KEY_ID=your_aws_access_key_id
export RCLONE_CONFIG_DEEP_SECRET_ACCESS_KEY=your_aws_secret_access_key
export RCLONE_CONFIG_DEEP_REGION=us-east-1
export RCLONE_CONFIG_DEEP_ACL=private
export RCLONE_CONFIG_DEEP_STORAGE_CLASS=DEEP_ARCHIVE
export RCLONE_CONFIG_DEEP_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export RCLONE_CONFIG_DEEP_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_DEEP_REMOTE=":s3:glacier-deep-archive-backup-ab"
#export RCLONE_S3_ACL
#export RCLONE_S3_BUCKET_ACL
#export RCLONE_S3_LOCATION_CONSTRAINT
#export RCLONE_S3_SERVER_SIDE_ENCRYPTION
#export RCLONE_S3_SSE_KMS_KEY_ID
#export RCLONE_S3_SESSION_TOKEN
#export RCLONE_S3_ENDPOINT
#export RCLONE_S3_PROVIDER
#export RCLONE_S3_ENV_AUTH=true

# Optional client-side crypt remote named "secret".
# Uncomment and set RCLONE_CONFIG_SECRET_REMOTE to the underlying remote
# (example: awsdeep:glacier-deep-archive-backup-ab) to use secret:path.
# rclone obscure is required; raw passwords are not accepted in env/config.
if [[ -n "${RCLONE_PASSWORD:-}" && -n "${RCLONE_SALT:-}" ]]; then
  export RCLONE_CONFIG_S3CRYPT_TYPE=crypt
  export RCLONE_CONFIG_S3CRYPT_FILENAME_ENCRYPTION=standard
  export RCLONE_CONFIG_S3CRYPT_DIRECTORY_NAME_ENCRYPTION=true
  export RCLONE_CONFIG_S3CRYPT_STORAGE_CLASS=STANDARD
  export RCLONE_CONFIG_S3CRYPT_PASSWORD="$(rclone obscure "$RCLONE_PASSWORD")"
  export RCLONE_CONFIG_S3CRYPT_PASSWORD2="$(rclone obscure "$RCLONE_SALT")"  
  export RCLONE_CONFIG_S3CRYPT_REMOTE=":s3:glacier-deep-archive-backup-ab"
 # export RCLONE_CONFIG_S3CRYPT_REMOTE=":DEEP:glacier-deep-archive-backup-ab"
fi

# Format: "Display Name|source|destination|bucket|storageClass"
# bucket may be an on-the-fly remote (:s3:bucket-name) or a named remote
# prefix (awsdeep:bucket-name). Destination is the path inside that bucket.
presets=(
 #1 "Backup Google Takeout to AWS DEEP Archive|/home/ab/Downloads/dtach/googleTakeout/|googletakeout/|:s3:glacier-deep-archive-backup-ab|DEEP_ARCHIVE"
  "Archive Gentoo25 to AWS Deep|/media/freespace/backups/gentoo25/|gentoo.backup|DEEP:glacier-deep-archive-backup-ab|DEEP_ARCHIVE"
  "Copy test.txt to AWS Encrypted|/media/freespace/test.txt|encrypted-standard-storage|S3CRYPT:|STANDARD"
  "Copy test.txt to AWS Encrypted|/media/freespace/test.txt|encrypted-standard-storage|S3CRYPT:|STANDARD"
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
  rclone copy "$source" "${bucket}/${destination}" --progress
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


#  export RCLONE_S3_TYPE=s3
#  export RCLONE_S3_PROVIDER=AWS
#  export RCLONE_S3_REGION=us-east-1
#  export RCLONE_S3_STORAGE_CLASS=DEEP_ARCHIVE
#  export RCLONE_S3_UPLOAD_CONCURRENCY=16
#  export RCLONE_S3_CHUNK_SIZE=16M
#export RCLONE_S3_ACL
#export RCLONE_S3_BUCKET_ACL
#export RCLONE_S3_LOCATION_CONSTRAINT
#export RCLONE_S3_SERVER_SIDE_ENCRYPTION
#export RCLONE_S3_SSE_KMS_KEY_ID
#export RCLONE_S3_SESSION_TOKEN
#export RCLONE_S3_ENDPOINT
#export RCLONE_S3_PROVIDER
 #export RCLONE_S3_ENV_AUTH=true