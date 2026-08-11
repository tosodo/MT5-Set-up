# Measured broker facts — PU Prime demo, 11 Aug 2026

Everything here was **measured**, not read off a website, by running
`mql5/Scripts/AccountDiagnostics.mq5` against the live terminal. Re-run it and
update this file whenever the account or broker changes — these numbers drive
EA inputs, and a stale number here is worse than no number.

Source run: `01:21:04` local / `03:21:04` server, XAUUSD.s H1.

## Account

| | |
|---|---|
| Login / server | 700132554 @ PUPrime-Demo |
| Company | PU Prime Ltd |
| Balance / equity | 1,000.00 **GBP** |
| Leverage | **1:500** |
| Margin mode | hedging |
| Terminal data folder | `C:\Program Files\MetaTrader 5` (portable-style — data lives in the install dir, not AppData) |

## Symbol: XAUUSD.s ("Gold US Dollar")

Note the `.s` suffix. Plain `XAUUSD` does not exist at this broker; a chart of
it opens blank and any EA attached to it fails to initialise.

| | |
|---|---|
| Trade mode | full access |
| Execution | market |
| **Filling modes advertised** | **IOC only** |
| Contract size | 100 oz per 1.00 lot |
| Lots min / max / step | 0.01 / 100.00 / 0.01 |
| Digits / point | 2 / 0.01 |
| Stops level | 20 points ($0.20 minimum SL/TP distance) |
| Freeze level | 0 |

**IOC only is the load-bearing fact.** An EA that hardcodes FOK gets every
order rejected with "Unsupported filling mode" while otherwise looking healthy.
`AgenticEA::ResolveFillingMode()` reads this at startup rather than assuming.

## Spread — measured, not assumed

60 samples over 15s, thin overnight session (~01:20 UK):

| min | median | mean | max |
|---|---|---|---|
| 31 | 32 | 32.2 | 36 |

Median spread = $0.32/oz = **£0.24 to cross at minimum size**.

The scaffold's placeholder gate of 30 points blocked **100% of samples**. Raised
to 60 in `AgenticEA.mq5`. Rationale: a spread gate exists to refuse trading
through a dislocation (news spike, rollover, illiquidity), not to shave
execution cost — so it belongs well above normal spread, not beside it.

**Not yet measured:** spread during London/NY hours, which should be tighter.
Re-run the diagnostic in an active session before treating 60 as final.

## Position sizing on £1,000

| | |
|---|---|
| Margin for 0.01 lot | £6.52 (0.7% of equity) |
| Value of 1 point at 0.01 lot | £0.0074 |
| A $1.00 gold move | £0.74 |
| 1% of equity (£10) buys a stop of | **1,351 points = $13.51** |

Margin is not the constraint; **granularity** is. 0.01 lot is the floor, so
£10 of risk buys roughly $13.50 of gold movement — around one hour's range for
this instrument. Any strategy needing a wider stop is risking more than 1% per
trade whether or not that was the intent, because the position cannot be made
smaller.

This makes the account fine for **proving the plumbing** and poor for
**judging whether a strategy works**. Do not read performance numbers off this
account as if they were representative.

## Open gap

There is **no position-size cap** in `RuleGuards.mqh`. The daily-loss and
drawdown guards are reactive — they measure equity that has already moved. At
1:500 leverage a single oversized order can breach both between consecutive
ticks. Per the repo's own rule ("every rule gets a guard, or gets written down
as an accepted risk"), this is recorded here as an open failure mode until a
pre-trade size check exists.
