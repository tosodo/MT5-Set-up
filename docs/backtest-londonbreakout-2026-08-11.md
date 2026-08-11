# Backtest — London breakout of the overnight range — 11 Aug 2026

**Hypothesis #1.** First strategy idea tested on this setup. Proposed and run
the same day. Verdict below is **inconclusive, and that is the finding** — the
rule was refused a size on 97% of the days it wanted to trade.

## What was tested

| | |
|---|---|
| EA | `mql5/Experts/Lab/LondonBreakoutLab.mq5` v1.00 |
| Symbol / timeframe | XAUUSD.s, M15 |
| Period | 2023.08.01 → 2026.08.01 (3 years, 70,983 bars) |
| Starting deposit | 1,000 GBP, leverage 1:500 |
| Tester model | **1-minute OHLC**, not real ticks |
| Risk settings | 2% per trade, 4% daily, 8% trailing drawdown — the live production values |

The rule: measure the high/low of 02:00–10:00 server time; in the 10:00–14:00
window, the first M15 bar to close outside that range opens a trade; stop at
the **midpoint** of the range; target 2× the stop distance; one trade per day;
flat by 21:00.

Position size was **not** a free parameter — it came from
`RuleGuards::MaxLotForStop()`, the same preventive size cap the production EA
uses. That decision is what produced the headline result.

## What actually happened

| | |
|---|---|
| Trading days seen | 775 |
| Days a breakout signal fired | 445 |
| **Days the risk engine refused to size the trade** | **431** |
| Days with no signal at all | 330 |
| **Trades taken** | **14** |
| Closed by the evening cutoff rather than SL/TP | 0 |
| Skipped for no measurable range / range too tight / guard block | 0 / 0 / 0 |

**14 trades in three years.** Every other skip reason was zero, so there is
exactly one cause: the stop was too wide to trade at a safe size.

### Why the stop was too wide

At 2% risk on a £1,000 account, and with 0.01 lots the smallest position PU
Prime allows, the account can afford a stop of **at most $27** of gold price
movement (2,700 points). See `broker-puprime-demo-2026-08-11.md`.

Half of an 8-hour gold range, plus the overshoot on the breakout bar itself,
is usually **more** than $27. So `MaxLotForStop()` returned 0.0 and the day was
skipped. The guard behaved correctly. The *rule* was incompatible with the
account, which is a design fault in the rule, not a fault in the guard.

## Result of the 14 trades that did happen

| | |
|---|---|
| Net profit | **−£21.67** (−2.2%) |
| Gross profit / loss | £148.37 / −£170.04 |
| Profit factor | 0.87 |
| Expected payoff | −£1.55 per trade |
| Sharpe ratio | −1.13 |
| Win rate | 28.6% (4 wins / 10 losses) |
| Long / short win rate | 12.5% (1 of 8) / 50.0% (3 of 6) |
| Average win / loss | £37.09 / −£17.00 |
| Largest win / loss | £39.99 / −£20.62 |
| **Max consecutive losses** | **5, costing £73.94** |
| **Balance drawdown, max** | **£73.94 (7.03%)** |
| **Equity drawdown, max** | **£84.36 (7.94%)** |

**This P&L figure means nothing.** 14 trades is far below the sample needed to
judge a strategy — 100+ before the number carries information. The idea was
not disproven here. It was never given a fair run.

The one structural signal worth keeping: **average win £37.09 vs average loss
£17.00**, a realised reward-to-risk of ~2.2. The 2R target worked as designed.
The rule lost because it won 29% of the time, and 2:1 needs ~34% to break even.

## The finding that matters most

**Equity drawdown reached 7.94% against a hard limit of 8.0%.**

A run of 5 consecutive losses came within 0.06 percentage points of ending the
account — on a strategy that took only 14 trades in three years. A rule that
traded at a normal frequency would reach that wall far sooner.

This is the arithmetic already written down in `rule-map-self-2026-08-11.md`:
at 2% per trade, 4 full-stop losses exhaust the 8% limit. The backtest produced
that outcome independently, on real price data, without being asked to.

Risk per trade was left at 2% by explicit decision on 11 Aug 2026, after a
recommendation to reduce it to 1% was declined. Recording that here because the
next run will hit the same wall, and the reason should not have to be
rediscovered.

## Caveats on the method

- **1-minute OHLC model, not real ticks.** Where a stop and a target fall inside
  the same minute the tester assumes the loss. Conservative, but the last few
  percent of any figure here is not trustworthy. Re-run survivors on real ticks
  (`Model=4`) before believing a precise number.
- Spread modelled by the tester, not by the live 31-point median measured on
  11 Aug 2026.
- One symbol, one 3-year window, no out-of-sample split. Nothing here has been
  validated against overfitting, because there is nothing yet worth validating.

## Next step

Not "try different parameters until it profits" — that is how a curve-fit gets
built. The specific, diagnosed problem is **stop width**, and the fix is to
shrink it until the account can actually take the trades:

1. Measure a shorter overnight window (final 4 hours rather than 8).
2. Place the stop a quarter of the way into the range rather than halfway.

Target: typical stop of $8–12, comfortably inside the $27 ceiling, unlocking
most of the 431 skipped days and producing a few hundred trades — a sample that
can answer the question.

**Expected trade-off, stated in advance so it cannot be rationalised later: a
tighter stop is hit more often, so the win rate should FALL.** The question is
whether it falls further than the extra trade frequency compensates for. If the
win rate stays flat or improves, be suspicious rather than pleased.
