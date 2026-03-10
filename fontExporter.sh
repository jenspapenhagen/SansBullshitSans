#!/bin/sh

set -eu

usage() {
  printf 'Usage: %s fontfilename\n' "$0" >&2
}

warn() {
  printf 'Warning: %s\n' "$1" >&2
}

write_wrapped_base64() {
  if command -v base64 >/dev/null 2>&1; then
    base64 < "$1" | tr -d '\n' | fold -w 72
    return 0
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl base64 -A -in "$1" | fold -w 72
    return 0
  fi

  printf 'Error: neither base64 nor openssl is available for encoding.\n' >&2
  exit 1
}

is_ttf_file() {
  [ -f "$1" ] || return 1
  header=$(od -An -t x1 -N 4 "$1" 2>/dev/null | tr -d ' \n')
  [ "$header" = "00010000" ]
}

resolve_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
    return 0
  fi

  dir_name=$(dirname "$1")
  base_name=$(basename "$1")
  (
    cd "$dir_name" &&
    printf '%s/%s\n' "$(pwd)" "$base_name"
  )
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

font_input=$1
if [ ! -f "$font_input" ]; then
  printf 'Error: font file not found: %s\n' "$font_input" >&2
  exit 1
fi

font_path=$(resolve_path "$font_input")
font_dir=$(dirname "$font_path")
font_name=$(basename "$font_path")
font_base_name=${font_name%.*}
if [ "$font_name" = "$font_base_name" ]; then
  font_ext=""
else
  font_ext=.${font_name##*.}
fi
font_ext=$(printf '%s' "$font_ext" | tr '[:upper:]' '[:lower:]')

ttf_out_file=$font_dir/$font_base_name.ttf
woff2_out_file=$font_dir/$font_base_name.woff2
out_file=$font_path.mobileconfig

if is_ttf_file "$font_path"; then
  if [ "$font_path" = "$ttf_out_file" ]; then
    printf 'TTF already present: %s\n' "$ttf_out_file"
  else
    cp "$font_path" "$ttf_out_file"
    printf 'Wrote %s\n' "$ttf_out_file"
  fi
elif [ "$font_ext" = ".ttx" ]; then
  if ! command -v ttx >/dev/null 2>&1; then
    warn "ttx tool not found; cannot export TTF from TTX input."
  else
    ttx -o "$ttf_out_file" "$font_path" >/dev/null
    if [ -f "$ttf_out_file" ]; then
      printf 'Wrote %s\n' "$ttf_out_file"
    else
      warn "ttx ran but did not produce $ttf_out_file."
    fi
  fi
elif [ "$font_ext" = ".woff2" ]; then
  if ! command -v woff2_decompress >/dev/null 2>&1; then
    warn "woff2_decompress not found; cannot export TTF from WOFF2 input."
  else
    woff2_decompress "$font_path" >/dev/null
    if [ -f "$ttf_out_file" ]; then
      printf 'Wrote %s\n' "$ttf_out_file"
    else
      warn "woff2_decompress ran but did not produce $ttf_out_file."
    fi
  fi
else
  warn "Input is not TTF/WOFF2. Skipping TTF export."
fi

if [ -f "$ttf_out_file" ]; then
  if ! command -v woff2_compress >/dev/null 2>&1; then
    warn "woff2_compress not found; cannot export WOFF2."
  else
    woff2_compress "$ttf_out_file" >/dev/null
    candidate_a=$ttf_out_file.woff2
    candidate_b=$woff2_out_file

    if [ -f "$candidate_a" ] && [ "$candidate_a" != "$woff2_out_file" ]; then
      mv -f "$candidate_a" "$woff2_out_file"
    fi

    if [ -f "$candidate_b" ]; then
      printf 'Wrote %s\n' "$woff2_out_file"
    elif [ "$font_ext" = ".woff2" ] && [ -f "$font_path" ]; then
      cp "$font_path" "$woff2_out_file"
      printf 'Wrote %s\n' "$woff2_out_file"
    else
      warn "woff2_compress ran but no WOFF2 output was found."
    fi
  fi
fi

payload_font_path=$font_path
if [ -f "$ttf_out_file" ]; then
  payload_font_path=$ttf_out_file
fi

if command -v uuidgen >/dev/null 2>&1; then
  outer_uuid=$(uuidgen)
  inner_uuid=$(uuidgen)
else
  outer_uuid=$(openssl rand -hex 16 2>/dev/null | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/')
  inner_uuid=$(openssl rand -hex 16 2>/dev/null | sed 's/^\(........\)\(....\)\(....\)\(....\)\(............\)$/\1-\2-\3-\4-\5/')
fi

if [ -z "${outer_uuid:-}" ] || [ -z "${inner_uuid:-}" ]; then
  printf 'Error: unable to generate UUIDs.\n' >&2
  exit 1
fi

hostname_value=$(hostname)
payload_font_name=$(basename "$payload_font_path")

{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
  printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  printf '%s\n' '<plist version="1.0">'
  printf '%s\n' '<dict>'
  printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$payload_font_name"
  printf '%s\n' '<key>PayloadIdentifier</key>'
  printf '<string>%s.%s</string>\n' "$hostname_value" "$outer_uuid"
  printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
  printf '<key>PayloadUUID</key><string>%s</string><key>PayloadVersion</key><integer>1</integer>\n' "$outer_uuid"
  printf '%s\n' '<key>PayloadContent</key>'
  printf '%s\n' '<array>'
  printf '%s\n' '<dict>'
  printf '%s\n' '<key>PayloadType</key><string>com.apple.font</string>'
  printf '%s\n' '<key>Font</key>'
  printf '%s\n' '<data>'
  write_wrapped_base64 "$payload_font_path"
  printf '%s\n' '</data>'
  printf '%s\n' '<key>Name</key>'
  printf '<string>%s</string>\n' "$payload_font_name"
  printf '%s\n' '<key>PayloadIdentifier</key>'
  printf '<string>%s.%s.com.apple.font.%s</string>\n' "$hostname_value" "$outer_uuid" "$inner_uuid"
  printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
  printf '<key>PayloadUUID</key><string>%s</string>\n' "$inner_uuid"
  printf '%s\n' '</dict>'
  printf '%s\n' '</array>'
  printf '%s\n' '</dict>'
  printf '%s\n' '</plist>'
} > "$out_file"

printf 'Wrote %s\n' "$out_file"
