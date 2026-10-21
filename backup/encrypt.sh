#!/usr/bin/env bash
# Verschlüsselt <datei> nach <zielordner>/ (data.enc, key.enc) für backup-public.pem.
# Zufälliger 256-Bit-Schlüssel je Datei; der Schlüssel selbst wird mit RSA-OAEP verschlüsselt.
set -euo pipefail
src="$1"; out="$2"
mkdir -p "$out"
key=$(openssl rand -hex 32)
openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -in "$src" -out "$out/data.enc" -pass "pass:$key"
printf '%s' "$key" | openssl pkeyutl -encrypt -pubin -inkey "$(dirname "$0")/backup-public.pem" \
  -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -out "$out/key.enc"
