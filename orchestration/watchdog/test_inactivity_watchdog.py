from datetime import datetime, timedelta, timezone

from inactivity_watchdog import check_inactivity, format_alert


def test_no_alert_when_fresh():
    last_trade = datetime.now(timezone.utc) - timedelta(days=1)
    status = check_inactivity(last_trade, threshold_days=5, alert_lead_days=2)
    assert not status.should_alert
    assert not status.should_escalate


def test_alert_fires_before_threshold():
    last_trade = datetime.now(timezone.utc) - timedelta(days=3.5)
    status = check_inactivity(last_trade, threshold_days=5, alert_lead_days=2)
    assert status.should_alert
    assert not status.should_escalate


def test_escalation_fires_near_threshold():
    last_trade = datetime.now(timezone.utc) - timedelta(days=4.2)
    status = check_inactivity(last_trade, threshold_days=5, alert_lead_days=2)
    assert status.should_escalate


def test_this_is_what_failed_fundingpips():
    # Reconstructing the actual failure mode: no alert existed at all, so the
    # threshold was crossed silently. This test just documents the gap conceptually —
    # wire real firm numbers into rule-map-template.md before the next attempt.
    last_trade = datetime.now(timezone.utc) - timedelta(days=10)
    status = check_inactivity(last_trade, threshold_days=7, alert_lead_days=2)
    assert status.should_escalate


def test_alert_messages_are_distinguishable():
    now = datetime(2026, 1, 10, tzinfo=timezone.utc)
    ok = check_inactivity(now - timedelta(days=1), 5, 2, now=now)
    warn = check_inactivity(now - timedelta(days=3.5), 5, 2, now=now)
    escalate = check_inactivity(now - timedelta(days=4.5), 5, 2, now=now)
    assert format_alert(ok, "TestFirm").startswith("OK")
    assert "⚠️" in format_alert(warn, "TestFirm")
    assert "ESCALATE" in format_alert(escalate, "TestFirm")
