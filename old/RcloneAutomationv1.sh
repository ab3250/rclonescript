#!/bin/bash
#AWSACCESSPLAINBASE:aws.crypt.base/
#AWSACCESSCRYPT:aws.crypt.base
#deep :s3:glacier-deep-archive-backup-ab
# Prevent history recording
#unset HISTFILE
set -euo pipefail
export GPG_TTY="${GPG_TTY:-$(tty)}"
# ======================== Get Secrets ===================
# blob contains 
# RCLONE_PASSWORD
# RCLONE_SALT
# RCLONE_S3_ACCESS_KEY_ID
# RCLONE_S3_SECRET_ACCESS_KEY
 
blob=$(tr -d '[:space:]' <<'EOF'
LS0tLS1CRUdJTiBQR1AgTUVTU0FHRS0tLS0tCgpoRjREYTlycnF5Q0dUZThTQVFk
QXVwcVAxMFZ1Ym1FMjVMcUl2TVRsNFgwN29GUTJjbk8zclFzUjlIUWY0WGd3CkZa
MFkxRldXZkxEOUt3ZFRxMndNcHRzYjIvcStPTUNrOVhzR3l4WXkvZ1NSR2NkeTVQ
VHZiaWhQYk94a0hoNW4KMU1Bd0FRa0NFSUxuUUdWeXZEbHpQQ2Fhc0VPSEV1OFVF
cjNqcHRvR1ZXSm9KUGRhQ2dLQ0pTNUk0NzErNndOUwpjVUdvUy9zYXhJUmU2QmRx
VkU0S3VuekQ2V1NNRDNHUEhreDdZYVhzY3JKZmtyZmJBR1VTakdWUW1uT2s4TDFm
CnBleG4yTEtXWDZMb1IxV28wU3ZCUUlUaEZ5bHYzWnBkQ2xoNFdtR0JxZ2NyeW9i
R1dwYUhDY1c5c3ZCQzVPNU0KVG1DVlFMcTZFSDdpQ1NoL3VISDVGald4OHpvQ2s5
WFlHWXoxai96aGpzU3ZZa1JIU1pXQ21YUWg2YzdsMEJ2RwpFdHMrMEoyU1J6eHFK
dDZycUFqd05CWDQxdkxqTzJDb2ZFSXY3MEVzV3FEWHVTakJheFpYM2ZFaGZOcWZ0
SzBBCkV6ZXAKPS8rWWIKLS0tLS1FTkQgUEdQIE1FU1NBR0UtLS0tLQo=
EOF
)

plain=$(printf '%s' "$blob" | base64 -d | gpg \
  --decrypt \
  --pinentry-mode=ask \
  --no-symkey-cache \
  --quiet \
  --no-greeting)

IFS=' ' read -ra pairs <<< "$plain"
for pair in "${pairs[@]}"; do
  [[ -z $pair ]] && continue
  key=${pair%%=*}
  val=${pair#*=}
  printf -v "$key" '%s' "$val"
  export "$key"  
done
unset blob
unset plain
# ======================== CONFIG RCLONE ========================
# ======================== CONFIG S3 PLAIN ======================
 export RCLONE_CONFIG=/dev/null
 export RCLONE_S3_TYPE=s3
 export RCLONE_S3_PROVIDER=AWS
 export RCLONE_S3_REGION=us-east-1
 export RCLONE_S3_STORAGE_CLASS=DEEP_ARCHIVE
 export RCLONE_S3_ENV_AUTH=true
#export RCLONE_S3_ACL
#export RCLONE_S3_BUCKET_ACL
#export RCLONE_S3_LOCATION_CONSTRAINT
#export RCLONE_S3_SERVER_SIDE_ENCRYPTION
#export RCLONE_S3_SSE_KMS_KEY_ID
#export RCLONE_S3_SESSION_TOKEN
#export RCLONE_S3_ENDPOINT
#export RCLONE_S3_PROVIDER
# ======================== CONFIG S3 Encrypted ======================
 export RCLONE_CONFIG_CRYPT_PASSWORD="$(rclone obscure "$RCLONE_PASSWORD")"
 export RCLONE_CONFIG_CRYPT_PASSWORD2="$(rclone obscure "$RCLONE_SALT")"
# export RCLONE_CONFIG_CRYPT_TYPE=crypt
# export RCLONE_CONFIG_CRYPT_REMOTE=AWSDEEP:/nas.24.08.01/encrypted/
#export RCLONE_CONFIG_SECRET_TYPE=crypt
#export RCLONE_CONFIG_SECRET_REMOTE="$ENC_DIR"
#export RCLONE_CONFIG_SECRET_FILENAME_ENCRYPTION=standard
#export RCLONE_CONFIG_SECRET_DIRECTORY_NAME_ENCRYPTION=true
#export RCLONE_CONFIG_SECRET_PASSWORD"
#export RCLONE_CONFIG_SECRET_PASSWORD2=
BW="250M"
RATE="1000G"


# ---------- Named presets ----------
# Format: "Display Name|source|destination|bucket|storageClass"
presets=(
  "Backup Google Takeout to AWS DEEP Archive|/home/ab/Downloads/dtach/googleTakeout/|googletakeout/|:s3:glacier-deep-archive-backup-ab|DEEP_ARCHIVE"
  "Archive Gentoo25 to AWS Deep|/media/freespace/gentoo25/|gentoo.backup|:s3:glacier-deep-archive-backup-ab|DEEP_ARCHIVE"
 # "Copy Gentoo25 to AWS Encrypted|/mnt/tmp1/gentoo25/|Dimg/Images/gentoo25/gentoo25.100126/|:s3:aws.crypt.base|STANDARD"
)

# ========================================================


echo

echo "=== rclone sync – Preset Launcher ==="
echo
echo "Available presets:"
echo

for i in "${!presets[@]}"; do
  name="${presets[$i]%%|*}"
  printf "  %2d) %s\n" $((i+1)) "$name"
done
echo

while true; do
  read -p "Enter the number of the preset you want: " choice

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

echo "Do you want a DRY-RUN? (no real changes)"
select dry in "Yes (add --dry-run)" "No (real sync)"; do
  case $REPLY in
    1) dry_run="--dry-run"; break ;;
    2) dry_run=""; break ;;
    *) echo "Invalid choice" ;;
  esac
done
echo

logfile="log-aws-${storageClass}-${bucket}-$(date +%F).log"
sock="$(date +%F_%H-%M-%S).sock"

cmd=(
  dtach -A "$sock"
  rclone copy "$source" "${bucket}/${destination}" 
  --log-file="$logfile"
  --log-level INFO
  --bwlimit-file "$BW"
  --cutoff-mode SOFT
  --max-transfer "$RATE"
  --progress
  --transfers=1
  --s3-upload-concurrency=16
  --s3-chunk-size=16M
)

[[ -n "$dry_run" ]] && cmd+=("$dry_run")

echo "================ PROPOSED COMMAND ================"
printcmd=("${cmd[@]}")
for i in "${!printcmd[@]}"; do
  if [[ "${printcmd[$i]}" == --s3-secret-access-key=* ]]; then
    printcmd[$i]='--s3-secret-access-key=***'
  fi
done
printf '%q ' "${printcmd[@]}"
echo
echo "=================================================="
echo

read -p "Type 'yes' to run this command (anything else cancels): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Cancelled."
  unset s3_access_key_id s3_secret_access_key
  exit 0
fi

echo
echo "Starting..."
"${cmd[@]}"
rc=$?
exit "$rc"

