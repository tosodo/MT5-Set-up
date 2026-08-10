# Security posture — this project

Posture: **Strict** (see the `ai-security-posture` skill). Rationale: real money,
prop-firm rule sensitivity, and the inactivity-rule failure showed that "hands-off"
needs *active* guardrails, not fewer checks.

## Autonomy boundary

- **Read-only MCP calls** (balance, ticks, symbol info, trade history, Strategy Tester
  reports): run freely, no approval needed.
- **State-changing MCP calls** (place/modify/close order, toggle AutoTrading, change EA
  parameters, attach/detach an EA): require **explicit human approval before executing**.
  "The watchdog says we're about to breach a cadence rule" is not an override — it is a
  reason to ask a human faster, not to skip asking.
- The command floor (recursive delete, force-push, pipe-to-shell → require approval)
  applies to any shell access on the VPS. No exceptions for trading urgency.

## Credentials

- MT5 credentials live only in `.env`, which is gitignored. Never in code, never in
  chat, never in a committed config file.
- Type credentials directly on the VPS or inject them from a secrets manager. Do not
  paste them into a Claude Code session — anything in a session transcript should be
  treated as disclosed.
- `orchestration/config/mcp_config.example.json` uses `${VAR}` placeholders on purpose.
  Never commit a version with values substituted in.

## Network

- The MCP port is **VPN-only** (Tailscale/WireGuard). Never expose it to the open
  internet. `vps/bootstrap.ps1` refuses to open the port to `0.0.0.0/0`.
- The MT5 terminal's WebRequest allow-list should contain only hosts you actually need.

## Audit trail

- Every Strategy Tester run that informs a go/no-go decision gets its report saved to
  `orchestration/reports/` and referenced by the commit hash of the EA that produced it.
  The HTML itself is gitignored (it's large); record the hash → report mapping in the
  commit message or a run log.
- Fail-closed is the default everywhere: `RuleGuards` blocks trading if it hasn't been
  initialised, and the watchdog escalates rather than deciding on its own.
