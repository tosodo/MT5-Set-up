# Rule Map — [FIRM NAME] — [DATE]

> Fill this in **before** attaching any EA to a new prop-firm account — not just the
> risk rules, *all* of them. Attempt 1 (FundingPips) failed on a cadence rule while the
> risk guards were working fine. Copy this file to `docs/rule-map-<firm>-<date>.md` and
> fill in the copy; leave this template blank.

Source of truth (paste the exact URL of the firm's rulebook page you read): ___
Date read: ___

## Risk rules

- Max daily loss: ___
- Max overall drawdown: ___
- Drawdown type — **static** (from initial balance) or **trailing** (from equity
  high-water mark)? ___
  ⚠️ `RuleGuards.mqh` defaults to **trailing**. Switch the baseline in `DrawdownOK()`
  to `s_initialBalance` if this firm is static.
- Max position size / leverage: ___

## Cadence rules  ⚠️ this category is what failed the FundingPips attempt

- Minimum trading days required: ___
- Maximum consecutive non-trading days allowed: ___
- Minimum trades per week/month: ___
- What counts as a "qualifying" trade (any fill? min duration? min lot?): ___

## Consistency rules

- Max % of total profit from a single day: ___

## Behavioral rules

- News-trading restricted? Y/N, window: ___
- Weekend holding allowed? Y/N
- Strategy-switching mid-challenge allowed? Y/N
- Signal-copying / EA-purchasing restrictions: ___

## Time rules

- Evaluation phase deadline: ___
- Challenge total duration: ___

## Guard-to-rule mapping

| Rule (above) | Guard implemented in | Status |
|---|---|---|
| Max daily loss | `RuleGuards.mqh` → `DailyLossOK()` | ☐ |
| Max drawdown | `RuleGuards.mqh` → `DrawdownOK()` | ☐ |
| Drawdown type (static vs trailing) | `RuleGuards.mqh` baseline choice | ☐ |
| **Inactivity/cadence** | **`inactivity_watchdog.py`** | ☐ |
| Consistency | (not yet built) | ☐ |
| News window | (not yet built) | ☐ |
| Weekend holding | (not yet built) | ☐ |
| Phase deadline countdown | (not yet built) | ☐ |

**Rule with no guard = an open failure mode.** Anything left unticked above is a
deliberate accepted risk, not an oversight — write down here why it's acceptable:

___
