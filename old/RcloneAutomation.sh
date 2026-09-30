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
# RCLONE_CONFIG_AWSDEEP_ACCESS_KEY_ID
# RCLONE_CONFIG_AWSDEEP_SECRET_ACCESS_KEY
 
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
  echo -e "$RCLONE_PASSWORD \n"
  echo -e "$RCLONE_SALT \n"
  echo -e "$RCLONE_CONFIG_AWSDEEP_ACCESS_KEY_ID \n"
  echo -e "$RCLONE_CONFIG_AWSDEEP_SECRET_ACCESS_KEY \n"

  
done

# ======================== CONFIG RCLONE========================

export RCLONE_CONFIG_SECRET_TYPE=crypt
#export RCLONE_CONFIG_SECRET_REMOTE="$ENC_DIR"
export RCLONE_CONFIG_SECRET_FILENAME_ENCRYPTION=standard
export RCLONE_CONFIG_SECRET_DIRECTORY_NAME_ENCRYPTION=true
#export RCLONE_CONFIG_SECRET_PASSWORD="$(rclone obscure "$RCLONE_PASSWORD")"
#export RCLONE_CONFIG_SECRET_PASSWORD2="$(rclone obscure "$RCLONE_SALT")"

# ======================== CONFIG S3 ========================
export RCLONE_CONFIG_AWSDEEP_TYPE="s3"
export RCLONE_CONFIG_AWSDEEP_PROVIDER="aws"
export RCLONE_CONFIG_AWSDEEP_REGION="us-east-1"


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
  --config=/dev/null
  --s3-provider AWS
  --s3-region=us-east-1
  --s3-storage-class "$storageClass"
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
unset s3_access_key_id s3_secret_access_key
exit "$rc"

