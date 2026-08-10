# Setup checklist

Work top to bottom. Steps 1–3 need nothing but this repo. Steps 4 onward need
decisions and infrastructure that only a human can provide.

## Phase 0 — verify the repo (no infrastructure needed)

1. Create a virtualenv and install test deps:
   ```bash
   python3 -m venv .venv && ./.venv/bin/pip install pytest
   ```
2. Run the watchdog tests. All should pass:
   ```bash
   ./.venv/bin/python -m pytest orchestration/watchdog/ -q
   ```
3. Read `SECURITY.md` and confirm you're happy with the autonomy boundary before
   anything touches a real account.

## Phase 1 — decisions (blocked on you, not on code)

4. **Choose the venue.** A new prop firm, or a personal live/demo MT5 account.
   Nothing above depends on this, but nothing below can start without it.
5. **Fill in the rule map.** Copy `docs/rule-map-template.md` to
   `docs/rule-map-<firm>-<date>.md` and complete *every* section — including cadence,
   consistency, behavioral and time rules, not just risk. Paste the URL of the rulebook
   page you actually read.
6. Transfer the numbers from the rule map into:
   - `AgenticEA.mq5` inputs `InpMaxDailyLossPct` / `InpMaxDrawdownPct`
   - the drawdown baseline in `RuleGuards.mqh` (**trailing vs static** — check which
     the firm uses; the default is trailing)
   - the inactivity threshold passed to `check_inactivity()`

## Phase 2 — infrastructure (blocked on you)

7. **Provision a Windows VPS**, region close to the eventual broker's server. Get IP
   and admin credentials.
8. **Set up the VPN** (Tailscale or WireGuard) between your Mac and the VPS. Device
   authorization is interactive.
9. **Install the MT5 terminal** on the VPS and log in to the broker account. GUI step.
10. **Tools → Options → Expert Advisors** — AutoTrading, the WebRequest allow-list, and
    the external-Python-API checkbox. GUI toggles today; see Phase 3 step 14.
11. **Create `.env`** from `.env.example` and fill in real credentials. Type them
    directly on the VPS or inject from a secrets manager — never paste into a chat.

## Phase 3 — bring it up (a later Claude Code session, once VPS access exists)

12. Run the bootstrap script from an elevated PowerShell on the VPS:
    ```powershell
    .\vps\bootstrap.ps1 -VpnSubnet "<your VPN CIDR>"
    ```
13. Copy `mql5/Experts/AgenticEA.mq5` and `mql5/Include/RuleGuards.mqh` into the
    terminal's data folder (`MQL5\Experts\` and `MQL5\Include\`), then compile in
    MetaEditor with F7. Expect 0 errors.
14. **Investigate the GUI-only settings from step 10** — some may have equivalents in
    the terminal's `.ini` config files under the data folder. If they do, script them.
    If they don't, document the exact click-path here.
15. Wire `inactivity_watchdog.py` to a scheduler (Windows Task Scheduler, or a simple
    loop), pulling `last_trade_time` from the MCP server's account-history tool.
16. **Attach the EA to a demo account first.** Do not skip demo.
17. Run a Strategy Tester pass, save the report to `orchestration/reports/`, and record
    the EA commit hash it came from (see `SECURITY.md`, audit trail).
