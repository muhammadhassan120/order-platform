from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List


def _normalize_total(total: Any) -> float:
    if isinstance(total, Decimal):
        return float(total)
    return float(total)


def build_invoice_payload(
    order_id: str,
    payment_ref: str,
    customer_email: str,
    items: List[Dict[str, Any]],
    total: Any,
) -> Dict[str, Any]:
    return {
        "order_id": order_id,
        "payment_ref": payment_ref,
        "customer_email": customer_email,
        "items": items,
        "total": _normalize_total(total),
        "issued_at": datetime.now(timezone.utc).isoformat(),
        "currency": "USD",
        "status": "COMPLETED",
    }


def build_invoice_s3_key(order_id: str, payment_ref: str) -> str:
    return f"invoices/{order_id}/{payment_ref}.json"