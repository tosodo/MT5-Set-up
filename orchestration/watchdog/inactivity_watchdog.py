"""
Inactivity watchdog — the guard that was missing on the FundingPips attempt.

Tracks days-since-last-qualifying-trade and alerts well before a firm's inactivity
threshold, rather than on the day it triggers. Firm-agnostic: the threshold is
configured per firm via docs/rule-map-template.md, not hardcoded.
"""

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional


@dataclass
class InactivityStatus:
    days_since_last_trade: float
    threshold_days: int
    alert_days: int
    should_alert: bool
    should_escalate: bool  # past the point where a human must act NOW


def check_inactivity(
    last_trade_time: datetime,
    threshold_days: int,
    alert_lead_days: int = 3,
    now: Optional[datetime] = None,
) -> InactivityStatus:
    """
    last_trade_time: timestamp of the most recent qualifying trade (UTC)
    threshold_days: the firm's actual inactivity limit (from rule-map-template.md)
    alert_lead_days: how many days BEFORE the threshold to start alerting.
                     This exists purely because "alert on the day it breaches" is
                     what already failed once — always alert with runway to act.
    """
    now = now or datetime.now(timezone.utc)
    elapsed = (now - last_trade_time).total_seconds() / 86400
    should_alert = elapsed >= (threshold_days - alert_lead_days)
    should_escalate = elapsed >= threshold_days - 1  # one day of runway left, or less
    return InactivityStatus(
        days_since_last_trade=elapsed,
        threshold_days=threshold_days,
        alert_days=alert_lead_days,
        should_alert=should_alert,
        should_escalate=should_escalate,
    )


def format_alert(status: InactivityStatus, firm_name: str) -> str:
    if status.should_escalate:
        return (
            f"🚨 ESCALATE — {firm_name}: {status.days_since_last_trade:.1f} days since "
            f"last trade, threshold is {status.threshold_days}. Human decision needed NOW "
            f"(force a compliant trade, or accept the risk)."
        )
    if status.should_alert:
        return (
            f"⚠️ {firm_name}: {status.days_since_last_trade:.1f} days since last trade, "
            f"threshold is {status.threshold_days}. Runway: "
            f"{status.threshold_days - status.days_since_last_trade:.1f} days."
        )
    return (
        f"OK — {firm_name}: {status.days_since_last_trade:.1f}/"
        f"{status.threshold_days} days."
    )
