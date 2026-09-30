#!/bin/bash
#AWSACCESSPLAINBASE:aws.crypt.base/
#AWSACCESSCRYPT:aws.crypt.base
#deep :s3:glacier-deep-archive-backup-ab
# Prevent history recording
unset HISTFILE

# ======================== CONFIG ========================
BW="250M"
RATE="1000G"

# GPG-encrypted credentials (public-key encrypted to the YubiKey).
# Create / replace with:
#   printf '%s\n' \
#     'ACCESS_KEY_ID=AKIA...' \
#     'SECRET_ACCESS_KEY=...' \
#     | gpg --encrypt --armor -r 6BDAEBAB20864DEF \
#         -o "${HOME}/.config/rclone-aws-creds.gpg"
CREDENTIALS_FILE="${HOME}/.config/rclone-aws-creds.gpg"
GPG_RECIPIENT="6BDAEBAB20864DEF"

# ---------- Named presets ----------
# Format: "Display Name|source|destination|bucket|storageClass"
presets=(
  "Backup Google Takeout to AWS DEEP Archive|/home/ab/Downloads/dtach/googleTakeout/|googletakeout/|:s3:glacier-deep-archive-backup-ab|DEEP_ARCHIVE"
  "Archive Gentoo25 to AWS Deep|/media/freespace/gentoo25/|gentoo.backup|:s3:glacier-deep-archive-backup-ab|DEEP_ARCHIVE"
 # "Copy Gentoo25 to AWS Encrypted|/mnt/tmp1/gentoo25/|Dimg/Images/gentoo25/gentoo25.100126/|:s3:aws.crypt.base|STANDARD"
)

# ========================================================

if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  echo "Error: Credentials file not found: $CREDENTIALS_FILE" >&2
  echo "Encrypt a new one to the YubiKey with:" >&2
  echo "  printf '%s\\n' 'ACCESS_KEY_ID=...' 'SECRET_ACCESS_KEY=...' |" >&2
  echo "    gpg --encrypt --armor -r $GPG_RECIPIENT -o $CREDENTIALS_FILE" >&2
  exit 1
fi

export GPG_TTY="${GPG_TTY:-$(tty)}"

echo "Decrypting credentials (YubiKey PIN, then touch if ENC touch is on)..."
creds=$(gpg --pinentry-mode ask --quiet --no-greeting --decrypt "$CREDENTIALS_FILE")
if [[ $? -ne 0 || -z "$creds" ]]; then
  echo "Error: Failed to decrypt $CREDENTIALS_FILE" >&2
  echo "Need User PIN + YubiKey. File must be encrypted to $GPG_RECIPIENT, not --symmetric." >&2
  exit 1
fi

s3_access_key_id=""
s3_secret_access_key=""

while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

  if [[ "$line" =~ ^ACCESS_KEY_ID= ]]; then
    s3_access_key_id="${line#ACCESS_KEY_ID=}"
  elif [[ "$line" =~ ^SECRET_ACCESS_KEY= ]]; then
    s3_secret_access_key="${line#SECRET_ACCESS_KEY=}"
  else
    if [[ -z "$s3_access_key_id" ]]; then
      s3_access_key_id="$line"
    elif [[ -z "$s3_secret_access_key" ]]; then
      s3_secret_access_key="$line"
    fi
  fi
done <<< "$creds"

unset creds

s3_access_key_id="${s3_access_key_id//[$'\t\r\n ']/}"
s3_secret_access_key="${s3_secret_access_key//[$'\t\r\n ']/}"

if [[ -z "$s3_access_key_id" || -z "$s3_secret_access_key" ]]; then
  echo "Error: Could not extract both ACCESS_KEY_ID and SECRET_ACCESS_KEY." >&2
  exit 1
fi

echo "Credentials loaded."
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
  --s3-access-key-id="$s3_access_key_id"
  --s3-secret-access-key="$s3_secret_access_key"
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
