#!/usr/bin/env bash
#
# run_backtest.sh — drive MT5's Strategy Tester headlessly over the Lab EA.
#
# WHY THIS IS SEPARATE FROM sync_and_compile.sh: this one *launches the
# terminal*. It therefore refuses to run while a terminal is already up, for
# the same reason the QA script does — MetaTrader is single-instance, so a
# running GUI silently swallows the /config: launch and you sit watching a
# test that never started. A terminal we did not start is very likely the
# user's live session; closing it is their call, not this script's.
#
# NO CREDENTIALS HERE, deliberately. The tester reuses the login the terminal
# already has saved. Account details do not belong in a committed file.
#
# Usage: scripts/run_backtest.sh [FROM_DATE] [TO_DATE]
#        scripts/run_backtest.sh 2023.08.01 2026.08.01
set -euo pipefail

PREFIX="${WINEPREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
MT5="$PREFIX/drive_c/Program Files/MetaTrader 5"

# Wine ships inside the MetaTrader app bundle and is NOT on PATH. Calling a
# bare `wine` here exits 127 (command not found) — and because the launch line
# below ends in `|| true`, that failure would otherwise be swallowed and the
# script would cheerfully report success having done nothing at all.
WINE_BIN="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine"
if [[ ! -x "$WINE_BIN" ]]; then
  echo "ERROR: wine not found at $WINE_BIN" >&2
  exit 1
fi
export WINEPREFIX="$PREFIX"

EXPERT="Lab\\LondonBreakoutLab"
SYMBOL="XAUUSD.s"
PERIOD="M15"
FROM="${1:-2023.08.01}"
TO="${2:-2026.08.01}"
DEPOSIT="1000"
CURRENCY="GBP"
LEVERAGE="500"
REPORT="LondonBreakoutLab_report"

if pgrep -f terminal64.exe >/dev/null 2>&1; then
  echo "REFUSING: a MetaTrader terminal is already running."
  echo "MT5 is single-instance — this launch would be silently ignored."
  echo "Close MetaTrader 5, then run this again."
  exit 1
fi

# The space-free symlink. Wine mishandles the spaces in 'Program Files' when
# passing a /config: path, and the launch becomes a silent no-op.
ln -sfn "$MT5" "$PREFIX/drive_c/mt5"

CONFIG="$MT5/config/backtest.ini"
mkdir -p "$MT5/config"

# Model=1 is '1 minute OHLC': fast enough for three years of gold, accurate
# enough to answer "does this idea have anything in it". It is NOT accurate
# enough to trust the last few percent of the result — when a stop and a target
# fall inside the same minute the tester assumes the loss. Re-run the survivors
# on real ticks (Model=4) before believing any precise number.
cat > "$CONFIG" <<EOF
[Tester]
Expert=$EXPERT
Symbol=$SYMBOL
Period=$PERIOD
Model=1
Optimization=0
ForwardMode=0
FromDate=$FROM
ToDate=$TO
Deposit=$DEPOSIT
Currency=$CURRENCY
Leverage=1:$LEVERAGE
Report=$REPORT
ReplaceReport=1
Visual=0
ShutdownTerminal=1
EOF

echo "Backtest: $EXPERT on $SYMBOL $PERIOD, $FROM -> $TO, $DEPOSIT $CURRENCY."
echo "First run downloads history from the broker and can take a long while."

rm -f "$MT5/$REPORT.htm" "$MT5/$REPORT.html" 2>/dev/null || true

LAUNCH_LOG="$MT5/backtest_launch.log"
"$WINE_BIN" "C:\\mt5\\terminal64.exe" "/config:C:\\mt5\\config\\backtest.ini" > "$LAUNCH_LOG" 2>&1 || true

echo "Terminal exited. Tester logs: $MT5/Tester/logs/"
ls -1t "$MT5"/${REPORT}.htm* 2>/dev/null && echo "Report written." || echo "No report file found — check the tester log."
