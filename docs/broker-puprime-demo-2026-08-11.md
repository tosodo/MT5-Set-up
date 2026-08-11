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

## Execution — confirmed by a live round trip

`mql5/Scripts/SmokeTest.mq5`, 03:41:08 server. One 0.01-lot buy, opened and
closed immediately.

| | |
|---|---|
| Filling mode used | IOC (resolved from the broker, not assumed) |
| Open | asked 4409.87, filled **4409.85**, 90 ms |
| Close | filled 4409.35, 85 ms |
| Slippage on entry | **−2.0 points — in our favour** |
| Commission | 0.00 |
| Swap | 0.00 |
| Net cost of the round trip | **−£0.37** |
| Positions left open | 0 |

**IOC is confirmed working, not merely advertised.** This was the one fact that
could not be established without sending an order.

Round-trip latency ~90 ms against a terminal ping of ~80 ms, so the broker adds
roughly 10 ms of its own. Nothing here rules out a strategy on latency grounds;
equally, nothing here supports one that needs sub-100 ms reaction.

**Realised cost exceeded quoted spread.** Quoted spread at preflight was 36
points; entry-to-exit came to **50 points** (£0.37). The gap is price movement
plus whatever the spread did during the ~0.2 s the position was held. This is a
single sample and should not be treated as a measured average — but it does
mean the quoted spread is a floor on cost, not an estimate of it. Assume worse.

At 1% risk (£10), **£0.37 is ~3.7% of the risk budget per round trip**. A
strategy has to clear that before it clears zero.

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

## Position-size cap — CLOSED

Previously recorded here as an open failure mode: the daily-loss and drawdown
guards are *reactive*, so at 1:500 leverage a single oversized order could
breach both between consecutive ticks with nothing to prevent it.

`RuleGuards::MaxLotForStop()` now sizes every trade in advance, taking the
smallest of: the per-trade risk budget, the room left to the daily limit, the
room left to the drawdown limit, minus whatever open positions could still
lose, and capped again at 50% of free margin. It returns `0.00` — trade
nothing — if any of those leave no room, if anything is open without a stop
loss, or if any input is missing. Rounding is always **down** to the lot step.

Verified against this live account by `AccountDiagnostics.mq5`, which checks
that a wider stop never permits a larger position, that a size one step above
the cap is rejected, that the cap itself is accepted, and that sizing without
a stop returns zero.

### What the cap means on £1,000 specifically

Because 0.01 lot is the floor, 1% risk (£10) covers a stop of about **1,350
points ($13.50)**. Ask for a wider stop and the cap correctly returns `0.00`:
the position cannot be made smaller, so the trade is skipped rather than
silently over-risked.

That is the right behaviour and an uncomfortable fact at the same time. Most
realistic gold stops are wider than $13.50, so **on this account at 1% risk the
EA will decline most trades**. The options are a higher risk % (a decision, not
a workaround), a smaller-contract instrument, or more capital. Nothing here is
a code problem — it is what £1,000 buys on gold, now made visible up front
instead of discovered after a loss.

## Remaining open items

- Spread was measured overnight only. Re-run the diagnostic during London/NY
  hours before treating the 60-point gate as final.
- Realised cost is one sample. Worth re-measuring before any cost assumption
  goes into a strategy.
