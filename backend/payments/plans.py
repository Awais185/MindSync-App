"""Plan catalog for Stripe PaymentSheet API — sourced from SubscriptionPlan rows (basic/premium)."""

from __future__ import annotations

from decimal import Decimal

from subscriptions.constants import PLAN_BASIC, PLAN_PREMIUM
from subscriptions.models import SubscriptionPlan

# Paid plans for Stripe PaymentSheet API.
PAID_PLAN_CODES = (PLAN_BASIC, PLAN_PREMIUM)

FEATURE_LABELS = {
    'emotion_detection_limited': 'Emotion detection (limited)',
    'emotion_detection_full': 'Full emotion detection',
    'basic_mood_tracking': 'Basic mood tracking',
    'screen_time': 'Screen time tracking',
    'chat_realtime_psychologist': 'Live psychologist chat',
    'content_monitoring': 'Content monitoring',
    'analytics_day_week_month': 'Day / week / month analytics',
    'ads_included': 'Ads included',
    'weekly_reports': 'Weekly reports',
    'no_ads': 'No ads',
    'personalized_suggestions': 'Personalized suggestions',
    'chat_digital_psychologist': 'Digital psychologist chat',
    'mental_health_monitoring': 'Mental health monitoring',
    'advanced_ai_insights': 'Advanced AI insights',
    'monthly_mental_health_reports': 'Monthly mental health reports',
    'therapist_recommendation': 'Therapist recommendations',
    'priority_support': 'Priority support',
    'parental_control': 'Parental controls',
    'full_app_access': 'Full app access',
}


def _feature_labels(raw: list) -> list[str]:
    out: list[str] = []
    for key in raw or []:
        k = str(key).strip()
        if not k:
            continue
        out.append(FEATURE_LABELS.get(k, k.replace('_', ' ').title()))
    return out


def plan_row_from_model(plan: SubscriptionPlan) -> dict:
    price_usd = Decimal(plan.price_usd)
    amount_cents = int(price_usd * 100)
    days = max(1, int(getattr(plan, 'duration_days', None) or 30))
    return {
        'id': plan.code,
        'display_name': plan.name,
        'price': amount_cents,
        'currency': 'usd',
        'duration_days': days,
        'features': _feature_labels(plan.features if isinstance(plan.features, list) else []),
        'plan_db_id': plan.id,
    }


def get_plan_by_code(plan_id: str) -> dict | None:
    code = (plan_id or '').strip().lower()
    if code not in PAID_PLAN_CODES:
        return None
    plan = SubscriptionPlan.objects.filter(code=code, is_active=True).first()
    if not plan:
        return None
    return plan_row_from_model(plan)


def list_public_plans() -> list[dict]:
    rows = []
    for code in PAID_PLAN_CODES:
        row = get_plan_by_code(code)
        if row:
            rows.append(row)
    return rows
