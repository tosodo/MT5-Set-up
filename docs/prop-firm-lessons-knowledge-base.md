# Prop Firm Challenge — Lessons Knowledge Base

A living document. Add a new "Incident" entry every time an attempt ends — pass or fail —
so the pattern-matching gets sharper over time instead of starting from zero each attempt.

---

## Incident Log

### Attempt 1 — FundingPips, $50k, 2-Step Flex — **FAILED**

- **Cause:** Breached FundingPips' inactivity rule (days without trading) — **not** a
  drawdown or losing-trade violation.
- **What that means:** the strategy/EA was not bleeding money. It went quiet during a
  stretch with no qualifying setups, and the account was disqualified purely for not
  trading within the required window.
- **Root cause category:** a rule-architecture gap. The build had guards for the *risk*
  rules (daily loss, max drawdown) but no guard for the *cadence* rule.

---

## The core lesson: "the rules" are not just the risk rules

Every prop firm publishes a rulebook, and it's tempting to read it as "don't lose too much,
too fast." That's only one category. A full rule map looks like:

| Category | Examples | Guard needed |
|---|---|---|
| **Risk** | Max daily loss, max overall drawdown, max leverage/position size | Kill-switch on breach |
| **Cadence** | Minimum trading days, max consecutive non-trading days, min trades/week | **Silence watchdog** — this is what got missed |
| **Consistency** | No single day > X% of total profit | Profit-distribution check across the challenge |
| **Behavioral** | No news-trading, no weekend holding, no strategy-switching mid-challenge, no signal-copying | Time-window / event-calendar gate |
| **Time** | Evaluation phase deadlines, challenge duration limits | Calendar countdown + alerting |

A fully autonomous, hands-off system is a double-edged sword: it removes emotional
override and manual error, but it also removes the human instinct to notice *"we haven't
traded in four days — is that a problem?"* If nothing in the system is explicitly watching
for silence, silence itself becomes the failure mode.

## Actionable rule for every future build

**Before writing a line of EA code**, extract every numeric and behavioral rule from the
prop firm's docs into a literal checklist, and build one automated guard per rule — not
just the ones about losing money. A cadence/silence guard is now a first-class requirement
alongside the risk guards, not an afterthought:

- Track days-since-last-qualifying-trade continuously
- Alert (or force a minimal, rule-compliant "keep-alive" action) well before the firm's
  inactivity threshold — not on the day it triggers
- Different firms set this threshold differently — re-derive it per firm, don't assume
  FundingPips' number carries over

## Technical patterns already validated (carried forward, still usable)

- ATR trailing stop, spread-limit gate, partial close at 1R → breakeven → trail — adapted
  from Evgeniy Kravchenko's "Trade Assistant" (MQL5 blog)
- Entry Time Offset (small millisecond delay before execution) — concept only, taken from a
  commercial "AI Prop Firms MT5" EA that was otherwise assessed as overfit/not trustworthy

## Open questions to resolve before the next attempt

- Which prop firm next, if any — inactivity thresholds and rule sets vary firm to firm, so
  this whole rule-map has to be redone, not copy-pasted
- Should the cadence guard force a compliant keep-alive trade automatically, or just alert
  a human to decide (extend / intervene / accept the risk)?
- Does this generalize to the separate Ghost/Alpaca project? Alpaca trades your own
  capital, so there's no prop-firm-style inactivity rule to violate — but the underlying
  principle (map every constraint, not just P&L ones, before automating) still applies to
  whatever venue-specific rules *do* exist there.

---

*Next entry: add here when the next attempt (any firm) concludes.*
