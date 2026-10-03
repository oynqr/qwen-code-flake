#!/usr/bin/env bash
set -euo pipefail

qwen=$1
here=$2
work=$(mktemp -d)
failed=0

python3 "$here/fake_openai.py" 18080 "$work/server.log" &
server=$!
trap 'kill $server' EXIT
for _ in $(seq 50); do
  if python3 -c 'import socket; socket.create_connection(("127.0.0.1", 18080))' 2>/dev/null; then break; fi
  sleep 0.1
done

scenario() {
  local name=$1 mode=$2 seed=$3
  shift 3
  local dir="$work/$name"
  mkdir -p "$dir/home" "$dir/proj"
  if [ -n "$seed" ]; then cp -r "$here/$seed/." "$dir/home/"; fi
  chmod -R u+w "$dir/home"
  : > "$work/server.log"
  (
    cd "$dir/proj"
    export HOME="$dir/home" XDG_CONFIG_HOME="$dir/home/.config" XDG_CACHE_HOME="$dir/home/.cache"
    export XDG_DATA_HOME="$dir/home/.local/share" XDG_STATE_HOME="$dir/home/.local/state" TERM=xterm-256color
    for kv in "$@"; do export "${kv?}"; done
    if [ "$mode" = p ]; then
      timeout 120 strace -f -qq -s 256 -e trace=connect,sendto,sendmsg -o "$dir/strace.log" \
        "$qwen" -p "say hello" > "$dir/stdout.log" 2> "$dir/stderr.log" || true
    else
      timeout 150 strace -f -qq -s 256 -e trace=connect,sendto,sendmsg -o "$dir/strace.log" \
        python3 "$here/drive_tui.py" "$dir/tui.log" "$qwen" || true
    fi
  )
  grep -E '(connect|sendto|sendmsg)\(' "$dir/strace.log" \
    | grep -E 'AF_INET6?|sun_path="[^"]*(resolve|nscd)' \
    | grep -vE 'sin_port=htons\(18080\), sin_addr=inet_addr\("127\.0\.0\.1"\)' \
    > "$dir/violations.log" || true
  local requests violations
  requests=$(grep -c '^POST /v1/chat/completions' "$work/server.log" || true)
  violations=$(wc -l < "$dir/violations.log")
  echo "$name: local LLM requests=$requests, outgoing violations=$violations"
  if [ "$violations" -ne 0 ]; then
    sed -E 's/^[0-9]+ +//' "$dir/violations.log" | sort | uniq -c
    failed=1
  fi
  if [ "$requests" -eq 0 ]; then
    cat "$dir/stderr.log" 2> /dev/null || true
    failed=1
  fi
}

env_config=(OPENAI_API_KEY=dummy OPENAI_BASE_URL=http://127.0.0.1:18080/v1 OPENAI_MODEL=local-model)

scenario env-noninteractive p "" "${env_config[@]}"
scenario env-interactive-extension tui seed-ext "${env_config[@]}"
scenario settings-noninteractive p seed-settings
scenario settings-interactive tui seed-settings

exit "$failed"
