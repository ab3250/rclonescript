plain='RCLONE_CONFIG_SECRET_TYPE=crypt|RCLONE_CONFIG_MYSECRET_PASSWORD=sedd'

blob=$(printf '%s' "$plain" | gpg \
  --symmetric \
  --pinentry-mode=loopback \
  --no-symkey-cache \
  --cipher-algo aes256 \
  --digest-algo sha256 \
  --s2k-digest-algo SHA512 \
  --s2k-cipher-algo AES256 \
  --s2k-mode 3 \
  --s2k-count 65011712 \
  --cert-digest-algo sha256 \
  --compress-algo none -z 0 \S
  --quiet \
  --no-greeting \
  --armor | base64 --wrap 0)

# one line (safe to store)
printf '%s\n' "$blob"

# or wrapped for a script heredoc
printf '%s\n' "$blob" | fold -w 64

blob=$(tr -d '[:space:]' <<'EOF'
LS0tLS1CRUdJTiBQR1AgTUVTU0FHRS0tLS0tCgpqQTBFQ1FNS2QyZVVjKzAvN1lq
LzBuVUJ6N3BPL3I4VGE2WGFkYnUrZE5mOVBGa1NLR294VHMzazMwaVBXVEVkCnFu
ek1LMjNxV3NLNFVucEI3TVAvOGpNQzRwNG1rZWpOMjRpdGs5b1hqY3BjQWtYMzV5
UzMxQWNrb2t2a0JMM2kKLytsT1h5KzRKRkpEUWEvdkh3Zzg3V21RK0FubXNqT3E4
QVdiYmJqYll3M1FUV2IwbFEwPQo9N09pbAotLS0tLUVORCBQR1AgTUVTU0FHRS0t
LS0tCg==
EOF
)

