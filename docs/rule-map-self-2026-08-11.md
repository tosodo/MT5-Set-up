# Rule Map — SELF-IMPOSED (no prop firm) — 11 Aug 2026

There is no firm yet. That is exactly why this file exists: the limits the EA
enforces are a **decision made on purpose**, not placeholders left in the code
until someone else supplies real numbers.

Source of truth: none external. These are our own limits, set from the
arithmetic below.
Account they apply to: PU Prime demo, 1,000.00 GBP, XAUUSD.s.

**When a venue is chosen, copy this file to `rule-map-<firm>-<date>.md`, fill it
from the firm's actual rulebook, and only then change the EA inputs.**

## Risk rules

- **Max daily loss: 4.0%** (`InpMaxDailyLossPct`)
- **Max overall drawdown: 8.0%** (`InpMaxDrawdownPct`)
- **Drawdown type: TRAILING**, from the equity high-water mark.
- Max position size / leverage: no fixed cap. Size is an *output* of
  `MaxLotForStop()`, bounded by the two limits above plus 50% of free margin.

### Why these numbers

Funded and evaluation accounts cluster at **4–5% daily** and **8–10% overall**.
Setting ours at the tight end of that band means a venue chosen later can only
ever *loosen* these. The reverse — discovering the rules are stricter than the
EA assumed — is the expensive direction, and is the failure this project has
already paid for once.

Same reasoning for choosing trailing drawdown: trailing is never looser than
static, so honouring a trailing 8% already honours a static 8%.

### What they mean in money on this account

| | % | Amount | Equity floor |
|---|---|---|---|
| Daily loss limit | 4.0% | £39.99 | £959.64 |
| Overall drawdown limit | 8.0% | £79.97 | £919.66 |

At the current 2% per trade (£19.99), **2 consecutive full-stop losses end the
trading day** and 4 reach the overall limit. The EA prints this count to the
journal at startup and warns if it ever degrades to 1.

That ratio is tight, and it is not a limits problem — it is what £1,000 buys on
gold, where the 0.01-lot minimum forces 2% per trade to get a tradable stop
width. See `broker-puprime-demo-2026-08-11.md`. The fix is a smaller-contract
instrument or more capital, not a looser limit.

### How the limits are actually enforced

`DailyLossOK()` / `DrawdownOK()` are **reactive** — they read equity that has
already moved, so on their own they only block the *next* trade.

What makes the limits hold is `MaxLotForStop()`, which runs *before* an order
exists. It refuses to size anything at all while a position is open without a
stop loss, and it sizes each new trade so the combined loss-to-stops across all
open positions stays inside the room left to **both** limits.

Every position stopped + total risk bounded in advance ⇒ open positions cannot
collectively breach the limits.

**The one thing that beats this:** a stop that doesn't fill near its price — a
weekend gap or a news spike. No software prevents that; only smaller size does.

## Cadence rules  ⚠️ this category is what failed the FundingPips attempt

No external rule exists — there is no firm imposing one. **Not "compliant",
just not applicable yet.** Every line here must be filled from a real rulebook
before any EA touches an evaluation account.

- Minimum trading days required: n/a
- Maximum consecutive non-trading days allowed: n/a
- Minimum trades per week/month: n/a
- What counts as a "qualifying" trade: n/a

## Consistency rules

- Max % of total profit from a single day: n/a (no firm)

## Behavioral rules

- News-trading restricted? No rule. The 60-point spread gate refuses to trade
  through a dislocation, which covers the *execution* risk but is not a
  news-window rule.
- Weekend holding allowed? No rule. Note the gap risk above — weekend-flat is
  worth adopting on its own merits, not just for compliance.
- Strategy-switching mid-challenge allowed? n/a
- Signal-copying / EA restrictions: n/a

## Time rules

- Evaluation phase deadline: n/a
- Challenge total duration: n/a

## Guard-to-rule mapping

| Rule (above) | Guard implemented in | Status |
|---|---|---|
| Max daily loss 4% | `RuleGuards.mqh` → `DailyLossOK()` | ☑ |
| Max drawdown 8% | `RuleGuards.mqh` → `DrawdownOK()` | ☑ |
| Drawdown type (trailing) | `RuleGuards.mqh` baseline choice | ☑ |
| Limits enforced *before* the order | `RuleGuards.mqh` → `MaxLotForStop()` | ☑ |
| **Inactivity/cadence** | **`inactivity_watchdog.py`** | ☐ no rule to enforce yet |
| Consistency | (not built) | ☐ no rule to enforce yet |
| News window | (not built) | ☐ no rule to enforce yet |
| Weekend holding | (not built) | ☐ no rule to enforce yet |
| Phase deadline countdown | (not built) | ☐ no rule to enforce yet |

**Rule with no guard = an open failure mode.** The unticked rows are unticked
because no such rule exists on a self-owned demo account — not because the risk
was assessed and accepted. The moment a venue is chosen, every one of them
becomes a real requirement, and the cadence row is the one that has already
failed an attempt before.
