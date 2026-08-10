#!/bin/bash
# sync_and_compile.sh — copy this repo's MQL5 source into the live MetaTrader 5
# install and compile it headlessly. Repo is the source of truth; the copy always
# goes repo -> terminal, never the other way.
#
#   ./scripts/sync_and_compile.sh
#
# What this does NOT do, on purpose: attach anything to a chart, or enable
# AutoTrading. Those are GUI actions, and they are the steps where a real order
# becomes possible. They stay yours. See SECURITY.md.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5"
MT5="$PREFIX/drive_c/Program Files/MetaTrader 5"
COMPILE="$HOME/.claude/skills/mql5-wine-qa/scripts/compile_mql5.sh"

EA_NAME="AgenticEA"

# --- preflight -------------------------------------------------------------
if pgrep -f "terminal64.exe" >/dev/null 2>&1; then
  echo "ABORT: MetaTrader 5 is running."
  echo "       Compiling into a live install while the terminal holds the files"
  echo "       gives unreliable results. Close MetaTrader and re-run."
  exit 1
fi

for p in "$MT5" "$COMPILE"; do
  [ -e "$p" ] || { echo "ABORT: not found: $p" >&2; exit 2; }
done

# --- sync ------------------------------------------------------------------
mkdir -p "$MT5/MQL5/Experts/$EA_NAME"
cp "$REPO/mql5/Experts/$EA_NAME.mq5" "$MT5/MQL5/Experts/$EA_NAME/$EA_NAME.mq5"
cp "$REPO/mql5/Include/RuleGuards.mqh" "$MT5/MQL5/Include/RuleGuards.mqh"
echo "synced: Experts/$EA_NAME/$EA_NAME.mq5 + Include/RuleGuards.mqh"

# --- compile ---------------------------------------------------------------
out="$("$COMPILE" "$PREFIX" "MQL5/Experts/$EA_NAME/$EA_NAME.mq5" 2>&1)"
result="$(echo "$out" | grep -E "^Result:" | tail -1)"

echo "$out" | grep -Ei "error|warning" | grep -v "generating code" | grep -v "^Result:" || true
echo "${result:-Result: (no result line — compile may not have run)}"

case "$result" in
  *"0 errors, 0 warnings"*) echo "OK — clean build."; exit 0 ;;
  *)                        echo "NOT CLEAN — fix the above before deploying."; exit 1 ;;
esac
