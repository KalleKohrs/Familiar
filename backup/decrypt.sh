#!/usr/bin/env bash
# Entschlüsselt einen Sicherungsordner (data.enc, key.enc) mit dem privaten Schlüssel.
# Aufruf: ./decrypt.sh <sicherungsordner> <privater-schlüssel.pem> <ziel.tar.gz>
set -euo pipefail
dir="$1"; private="$2"; target="$3"
key=$(openssl pkeyutl -decrypt -inkey "$private" -in "$dir/key.enc" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256)
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in "$dir/data.enc" -out "$target" -pass "pass:$key"
echo "entschlüsselt: $target"
