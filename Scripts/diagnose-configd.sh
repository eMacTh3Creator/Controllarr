#!/bin/sh
#
# diagnose-configd.sh — run on the machine that panicked (the Mac Studio).
#
# Read-only. Collects the data needed to find out why configd hung and whether
# Controllarr's network activity is implicated:
#   - the most recent kernel panic(s) and whether they're the configd watchdog
#   - what configd / mDNSResponder / watchdogd logged in the 12 minutes before
#     the panic (this is the key evidence)
#   - whether Controllarr was running torrents at the time
#   - Controllarr's network-relevant settings (DHT / PeX / LSD / connection
#     limits / VPN binding) — secrets are explicitly excluded
#
# Output is written to ~/controllarr-diag/ and a summary is printed. Share the
# summary (or the whole folder) back.
#
# Usage:  sh diagnose-configd.sh

set -u
OUT="$HOME/controllarr-diag"
mkdir -p "$OUT"

echo "===================================================================="
echo "Host: $(sysctl -n hw.model)   macOS $(sw_vers -productVersion 2>/dev/null)"
echo "Now:  $(date '+%Y-%m-%d %H:%M:%S %z')"
echo "===================================================================="

echo
echo "== Kernel panics on this Mac =="
ls -lt /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -8 || echo "  (none found)"

P="$(ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -1)"
if [ -n "${P:-}" ]; then
    echo
    echo "Latest panic: $P"
    echo "Type:        $(grep -m1 -iE 'watchdog|configd|panic\(' "$P" 2>/dev/null)"
    END="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$P" 2>/dev/null)"
    START="$(date -j -v-12M -f '%Y-%m-%d %H:%M:%S' "$END" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    echo "Window:      $START  ->  $END  (12 min before the panic)"

    echo
    echo "== configd / mDNSResponder / watchdogd around the panic =="
    log show --start "$START" --end "$END" --info \
        --predicate 'process IN {"configd","mDNSResponder","watchdogd"} OR eventMessage CONTAINS[c] "watchdog"' \
        > "$OUT/configd-window.txt" 2>/dev/null
    echo "  saved $(wc -l < "$OUT/configd-window.txt" | tr -d ' ') lines to $OUT/configd-window.txt"
    echo "  --- last 50 lines ---"
    tail -50 "$OUT/configd-window.txt"

    echo
    echo "== Was Controllarr active in that window? =="
    log show --start "$START" --end "$END" --info \
        --predicate 'process == "Controllarr" OR senderImagePath CONTAINS[c] "Controllarr"' \
        > "$OUT/controllarr-window.txt" 2>/dev/null
    echo "  $(wc -l < "$OUT/controllarr-window.txt" | tr -d ' ') Controllarr log lines in the window"
    tail -15 "$OUT/controllarr-window.txt"
else
    echo "  No .panic files — has the machine been reset, or are panics stored elsewhere?"
fi

echo
echo "== Controllarr right now =="
pgrep -lf -i controllarr 2>/dev/null || echo "  not currently running"

echo
echo "== Network footprint (if running) =="
PIDS="$(pgrep -i controllarr 2>/dev/null)"
if [ -n "${PIDS:-}" ]; then
    for pid in $PIDS; do
        echo "  pid $pid open sockets: $(lsof -nP -p "$pid" 2>/dev/null | grep -c -iE 'TCP|UDP')"
    done
fi

echo
echo "== Controllarr network settings (secrets excluded) =="
SD="$HOME/Library/Application Support/com.controllarr.Controllarr"
echo "  state dir: $SD"
find "$SD" -name '*.fastresume' 2>/dev/null | wc -l | tr -d ' ' | sed 's/^/  fastresume files (~torrents): /'
STATE="$(find "$SD" -name 'state.json' 2>/dev/null | head -1)"
if [ -n "${STATE:-}" ]; then
    /usr/bin/python3 - "$STATE" <<'PY' 2>/dev/null || echo "  (could not parse state.json)"
import json, sys
d = json.load(open(sys.argv[1]))
s = d.get("settings", d)
want = ("dht","pex","lsd","discovery","connection","peer","vpn","listen","port")
deny = ("password","secret","apikey","api_key","token","key")
for k in sorted(s):
    kl = k.lower()
    if any(t in kl for t in want) and not any(t in kl for t in deny):
        print(f"  {k} = {s[k]}")
PY
fi

echo
echo "== Done. Share the printed summary above (and ~/controllarr-diag/configd-window.txt). =="
