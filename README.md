# MT5 Agentic Trading

An MT5 trading setup where a deterministic Expert Advisor (EA) makes the trading
decisions, and an orchestration layer (Claude + an MCP server) watches, reports, and
escalates — but never trades on its own.

**Status:** scaffolding built. No venue chosen, no VPS provisioned, nothing live.

## The one-paragraph version

Attempt 1 (FundingPips, $50k, 2-Step Flex) **failed on an inactivity rule, not on
losses.** The EA had guards for the risk rules — daily loss, max drawdown — and no
guard at all for the cadence rules. It went quiet during a stretch with no qualifying
setups and got disqualified for silence. So the architecture here splits the guards in
two on purpose: risk guards live *inside* the EA where they can block a trade on the
tick, and cadence guards live *outside* it in the orchestration layer, where they can
see "nothing has happened for four days" — something an EA that only wakes on ticks is
structurally bad at noticing.

## Layout

| Path | What it is |
|---|---|
| `mql5/Experts/AgenticEA.mq5` | The EA skeleton. Decides trades. Risk guards wired in, strategy logic still TODO. |
| `mql5/Include/RuleGuards.mqh` | Daily-loss, drawdown and spread guards. Fail-closed. |
| `orchestration/watchdog/` | The inactivity watchdog — the guard that was missing. Pure logic, unit-tested, no MT5 needed. |
| `orchestration/config/` | Example MCP server config (placeholders only, never real values). |
| `orchestration/reports/` | Strategy Tester reports, one per commit hash. Gitignored contents. |
| `vps/bootstrap.ps1` | Windows VPS provisioning. Idempotent. Opens the MCP port to a VPN subnet only. |
| `docs/rule-map-template.md` | **Fill this in before every new attempt.** Every rule, not just the money ones. |
| `docs/prop-firm-lessons-knowledge-base.md` | Incident log. Add an entry every time an attempt ends, pass or fail. |
| `SECURITY.md` | Autonomy boundary: read-only calls run freely, state-changing calls need a human. |
| `SETUP.md` | The numbered checklist to get from this repo to something running. |

## Design rules worth not forgetting

1. **Every rule gets a guard, or gets written down as an accepted risk.** A rule with
   neither is an open failure mode. `docs/rule-map-template.md` is where that's tracked.
2. **Cadence guards live outside the EA.** Don't duplicate inactivity logic into
   `AgenticEA.mq5` — an EA can't reliably notice its own silence.
3. **Alert with runway, not on the breach.** The watchdog fires days before the
   threshold, because "alert on the day it breaches" is what already failed once.
4. **Fail closed.** An uninitialised guard blocks trading. A watchdog that isn't sure
   escalates to a human.
5. **The EA is the ownable IP.** Claude orchestrates and monitors; the EA decides.

## Running the tests

```bash
python3 -m venv .venv && ./.venv/bin/pip install pytest && ./.venv/bin/python -m pytest orchestration/watchdog/ -q
```

No MT5 terminal, broker account or VPS required for this — the watchdog is pure logic.
