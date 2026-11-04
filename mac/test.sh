#!/bin/bash
# macOS acceptance test for ddir — mirrors docs/mac-agent-task.md §4.
# Only touches TextEdit windows that this script opens itself (never the user's apps).
#
#   ./mac/test.sh            run against the installed app (default)
#   ./mac/test.sh --build    rebuild + reinstall first
set -uo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "--build" ]; then ./build.sh || exit 1; fi

DDIR="${DDIR_BIN:-$HOME/Applications/Ddir.app/Contents/MacOS/Ddir}"
[ -x "$DDIR" ] || DDIR="$(command -v ddir)"
[ -x "$DDIR" ] || { echo "ddir not found: run ./mac/build.sh first"; exit 1; }

export DDIR_HOME="$(mktemp -d /tmp/ddir-test.XXXXXX)"
WORK="$(mktemp -d /tmp/ddir-docs.XXXXXX)"
export DDIR_AGENT="ddirtest-$$"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL  $1  ${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
json() { python3 -c "import json,sys;d=json.load(sys.stdin);print($1)"; }
ddir_list() { "$DDIR" list; }

echo "== binary $DDIR"
echo "== state  $DDIR_HOME"

# 0. selftest
OUT="$("$DDIR" selftest 2>&1)"; RC=$?
echo "$OUT" | sed 's/^/   /'
check "selftest 7/7" "$(echo "$OUT" | grep -c '^PASS')" "7"
check "selftest exit 0" "$RC" "0"

# 1. mode + list
"$DDIR" mode semi >/dev/null
N=$("$DDIR" list | json 'len(d["windows"])')
[ "$N" -ge 3 ] && ok "list sees >=3 windows ($N)" || bad "list sees >=3 windows" "got $N"
TITLED=$("$DDIR" list | json 'sum(1 for w in d["windows"] if w["title"].strip())')
check "list titles non-empty" "$TITLED" "$N"

# 2. three TextEdit documents of our own (never touch windows that existed before)
PRE="$(ddir_list | python3 -c "import json,sys;d=json.load(sys.stdin);print(' '.join(w['hwnd'] for w in d['windows'] if w['app']=='TextEdit'))")"
for f in a b c; do printf 'line1\nline2\nline3\n' > "$WORK/$f.txt"; done
for f in a b c; do open -a TextEdit "$WORK/$f.txt"; sleep 1.0; done
sleep 1.0
# map title -> ref, only for windows this run opened
EVAL="$(ddir_list | PRE="$PRE" python3 -c '
import json,os,sys
pre=set(os.environ["PRE"].split())
d=json.load(sys.stdin)
got={}
for w in d["windows"]:
    if w["app"]=="TextEdit" and w["hwnd"] not in pre:
        got.setdefault(w["title"].strip(), w["hwnd"])
for k,v in got.items():
    print("R_"+k.replace(".","_")+"="+v)
')"
eval "$EVAL"
A="${R_a_txt:-}"; B="${R_b_txt:-}"; C="${R_c_txt:-}"
ref_of() { ddir_list | python3 -c "import json,sys;d=json.load(sys.stdin);print(next((w['hwnd'] for w in d['windows'] if w['app']=='TextEdit' and w['title'].strip()=='$1'),''))"; }
rect_of() { ddir_list | python3 -c "import json,sys;d=json.load(sys.stdin);print(next((','.join(map(str,w['rect'])) for w in d['windows'] if w['app']=='TextEdit' and w['title'].strip()=='$1'),''))"; }
[ -n "$A" ] && [ -n "$B" ] && [ -n "$C" ] && ok "TextEdit windows found ($A $B $C)" || bad "TextEdit windows found" "refs=$A $B $C"
[ -n "$A" ] || { echo "RESULT: $PASS passed, $FAIL failed"; exit 1; }

# 3. move + readback (<=1pt)
"$DDIR" move --window "$A" --rect "240,160,600,500" --force >/dev/null
check "move readback" "$(rect_of a.txt)" "240,160,600,500"
PRE_A="$(rect_of a.txt)"   # claim/release must come back to where the window was pre-claim

# 4. hide (app level) then release
"$DDIR" hide --window "$A" >/dev/null
HID=$(ddir_list | A="$A" python3 -c 'import json,os,sys;d=json.load(sys.stdin);a=os.environ["A"];print(all(w["hidden"] for w in d["windows"] if w["hwnd"]==a))')
check "hide marks TextEdit hidden" "$HID" "True"
"$DDIR" release >/dev/null; sleep 0.5
SHOWN=$(ddir_list | A="$A" python3 -c 'import json,os,sys;d=json.load(sys.stdin);a=os.environ["A"];print(any(w["hidden"] for w in d["windows"] if w["hwnd"]==a))')
check "release unhides" "$SHOWN" "False"

# 5. claim two windows side by side, then release restores the originals
ORIG_B="$(rect_of b.txt)"
"$DDIR" claim --needs "a.txt,b.txt" --force >/dev/null; sleep 0.4
RA="$(rect_of a.txt)"; RB="$(rect_of b.txt)"
python3 - "$RA" "$RB" <<'PY' && ok "claim: equal width, side by side" || bad "claim: equal width, side by side" "$RA / $RB"
import sys
a = [int(v) for v in sys.argv[1].split(",")]
b = [int(v) for v in sys.argv[2].split(",")]
assert a[2] == b[2], "widths differ"
assert a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0], "overlap"
assert a[1] == b[1] and a[3] == b[3], "not aligned"
PY
"$DDIR" release >/dev/null; sleep 0.4
check "release restores a.txt" "$(rect_of a.txt)" "$PRE_A"
check "release restores b.txt" "$(rect_of b.txt)" "$ORIG_B"

# 6. own + close: window disappears, process stays alive
"$DDIR" own --app TextEdit >/dev/null
"$DDIR" close --window "$C" >/dev/null
sleep 0.5
if ddir_list | json "any(w[\"hwnd\"] == '$C' for w in d[\"windows\"])" | grep -q True; then
  bad "close removes window" "c.txt still listed"
else
  ok "close removes window"
fi
PG="$(/usr/bin/pgrep -f "TextEdit" | head -1)"
[ -n "$PG" ] && ok "close keeps process alive (pid $PG)" || bad "close keeps process alive"
"$DDIR" disown --app TextEdit >/dev/null

# 7. policy guards
check "mode_off guard" "$(DDIR_HOME="$DDIR_HOME" "$DDIR" mode off >/dev/null; "$DDIR" move --window "$A" --rect 0,0,100,100 2>/dev/null | json 'd["error"]')" "mode_off"
"$DDIR" mode semi >/dev/null
OWNED=$("$DDIR" claim --needs "a.txt" --force >/dev/null; "$DDIR" list --text | awk -F'\t' -v t="a.txt" '$5==t{print $1;exit}')
check "close needs own" "$("$DDIR" close --window "$OWNED" | json 'd["error"]')" "not_owned"
"$DDIR" release >/dev/null

# 8. auto pipeline: arm -> minimize -> undo (auto_close=minimize, never closes windows)
win_field() { ddir_list | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(next((w[sys.argv[2]] for w in d["windows"] if w["hwnd"]==sys.argv[1]), "missing"))' "$1" "$2"; }
"$DDIR" mode auto >/dev/null
"$DDIR" config auto_close minimize >/dev/null
ARMED="$("$DDIR" auto on --seconds 1 2>/dev/null | tail -1)"
check "auto armed" "$(echo "$ARMED" | json 'd["armed"]')" "True"
MIN="$("$DDIR" auto close --app "a.txt" 2>/dev/null | tail -1)"
check "auto close minimized 1" "$(echo "$MIN" | json 'd["closed"]')" "1"
sleep 0.5
check "window is minimized" "$(win_field "$A" minimized)" "True"
UD="$("$DDIR" auto undo | json 'd["relaunched"]')"
[ "$UD" -ge 1 ] && ok "auto undo restored ($UD)" || bad "auto undo restored" "got $UD"
sleep 0.8
check "window no longer minimized" "$(win_field "$A" minimized)" "False"
"$DDIR" config auto_close off >/dev/null
"$DDIR" mode semi >/dev/null

# 9. focus token: only one holder at a time
check "focus acquire" "$(DDIR_AGENT=ft-a "$DDIR" focus --seconds 60 | json 'd["ok"]')" "True"
check "focus denied to other" "$(DDIR_AGENT=ft-b "$DDIR" focus | json 'd["error"]')" "focus_denied"
check "focus release" "$(DDIR_AGENT=ft-a "$DDIR" focus release | json 'd["ok"]')" "True"
check "focus re-acquire by b" "$(DDIR_AGENT=ft-b "$DDIR" focus --seconds 5 | json 'd["ok"]')" "True"
DDIR_AGENT=ft-b "$DDIR" focus release >/dev/null

# 10. concurrency: two agents claiming the same window -> exactly one wins, atomically
"$DDIR" release >/dev/null 2>&1
( DDIR_AGENT=race-a "$DDIR" claim --needs "a.txt" --force > /tmp/ddir-race-a.json ) &
( DDIR_AGENT=race-b "$DDIR" claim --needs "a.txt" --force > /tmp/ddir-race-b.json ) &
wait
WINS=$(python3 -c "import json;print(sum(1 for f in ('/tmp/ddir-race-a.json','/tmp/ddir-race-b.json') if json.load(open(f)).get('ok')))")
check "exclusive claim: one winner" "$WINS" "1"
check "exclusive claim: loser code" "$(python3 -c "import json;d=[json.load(open(f)) for f in ('/tmp/ddir-race-a.json','/tmp/ddir-race-b.json')];print([x.get('error') for x in d if not x.get('ok')][0])")" "window_owned_by"
DDIR_AGENT=race-a "$DDIR" release >/dev/null 2>&1; DDIR_AGENT=race-b "$DDIR" release >/dev/null 2>&1

# 11. an expired lease must not block a new claim
"$DDIR" release >/dev/null 2>&1
printf '%s\tstale-agent\tmove\t0,0,100,100\t0,0,100,100\t1\tls_dead\tnormal\t1\n' "$A" >> "$DDIR_HOME/leases.tsv"
check "expired lease ignored" "$(DDIR_AGENT=fresh "$DDIR" claim --needs "a.txt" --force | json 'd["ok"]')" "True"
DDIR_AGENT=fresh "$DDIR" release >/dev/null 2>&1

# 12. tray wiring (read-only: builds the NSMenu tree, does not start the agent)
TRAY="$("$DDIR" tray --check)"
check "tray --check ok" "$(echo "$TRAY" | json 'd["ok"]')" "True"
check "tray menu has 模式" "$(echo "$TRAY" | json 'any(i.get("title")=="模式" for i in d["menu"])')" "True"
check "tray menu has 全部还原" "$(echo "$TRAY" | json 'any(i.get("title","").startswith("全部还原") for i in d["menu"])')" "True"
check "tray menu has 退出" "$(echo "$TRAY" | json 'any(i.get("title")=="退出" for i in d["menu"])')" "True"
check "hud --check ok" "$("$DDIR" hud --check | json 'd["ok"] and d["tiles"] >= 1 and d["accessibility"]')" "True"

check "autostart reports state" "$("$DDIR" autostart status | json 'isinstance(d["enabled"], bool) and d["plist"].endswith(".plist")')" "True"

# cleanup: close only the windows this script opened
"$DDIR" own --app TextEdit >/dev/null 2>&1
for t in a.txt b.txt; do
  r="$(ref_of "$t")"; [ -n "$r" ] && "$DDIR" close --window "$r" >/dev/null 2>&1
done
rm -rf "$WORK" "$DDIR_HOME"
echo "---"
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
