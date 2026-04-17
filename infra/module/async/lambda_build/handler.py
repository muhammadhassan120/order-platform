import json
import logging
import os
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Dict, List

import boto3
import pg8000

from invoice_generator import build_invoice_payload, build_invoice_s3_key


logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")
sns = boto3.client("sns")
secretsmanager = boto3.client("secretsmanager")


def _json_default(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    raise TypeError(f"Type {type(value)} is not JSON serializable")


def get_env(name: str, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if value is None or value == "":
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def get_db_credentials() -> Dict[str, str]:
    secret_arn = get_env("DB_SECRET_ARN")
    response = secretsmanager.get_secret_value(SecretId=secret_arn)
    secret_string = response.get("SecretString")

    if not secret_string:
        raise ValueError("SecretString not found in Secrets Manager response")

    creds = json.loads(secret_string)

    username = creds.get("username")
    password = creds.get("password")

    if not username or not password:
        raise ValueError("Database secret must contain 'username' and 'password'")

    return {
        "username": username,
        "password": password,
    }


def get_db_connection():
    creds = get_db_credentials()

    db_host = get_env("DB_HOST")
    db_name = get_env("DB_NAME")
    db_port = int(os.getenv("DB_PORT", "5432"))

    return pg8000.connect(
        user=creds["username"],
        password=creds["password"],
        host=db_host,
        port=db_port,
        database=db_name,
        timeout=10,
    )


def put_invoice_to_s3(bucket_name: str, key: str, invoice_payload: Dict[str, Any]) -> None:
    s3.put_object(
        Bucket=bucket_name,
        Key=key,
        Body=json.dumps(invoice_payload, default=_json_default, indent=2).encode("utf-8"),
        ContentType="application/json",
    )


def update_order_in_rds(
    conn,
    order_id: str,
    payment_ref: str,
    invoice_key: str,
) -> None:
    with conn.cursor() as cursor:
        cursor.execute(
            """
            UPDATE orders
            SET status = %s,
                payment_ref = %s,
                invoice_key = %s,
                processed_at = NOW()
            WHERE id = %s
            """,
            ("COMPLETED", payment_ref, invoice_key, order_id),
        )
    conn.commit()


def write_audit_log(
    table_name: str,
    order_id: str,
    payment_ref: str,
    invoice_key: str,
) -> None:
    table = dynamodb.Table(table_name)

    ttl_value = int((datetime.now(timezone.utc) + timedelta(days=90)).timestamp())

    table.put_item(
        Item={
            "PK": f"ORDER#{order_id}",
            "SK": f"EVENT#{datetime.now(timezone.utc).isoformat()}",
            "event_type": "ORDER_COMPLETED",
            "payment_ref": payment_ref,
            "invoice_key": invoice_key,
            "ttl": ttl_value,
        }
    )


def publish_order_notification(topic_arn: str, order_id: str, customer_email: str, total: Any) -> None:
    sns.publish(
        TopicArn=topic_arn,
        Subject=f"Order {order_id} confirmed",
        Message=json.dumps(
            {
                "order_id": order_id,
                "email": customer_email,
                "total": total,
            },
            default=_json_default,
        ),
    )


def process_order_message(body: Dict[str, Any]) -> Dict[str, Any]:
    order_id = str(body["order_id"])
    customer_email = body["customer_email"]
    items = body["items"]
    total = body["total"]

    table_name = get_env("AUDIT_TABLE")
    bucket_name = get_env("INVOICE_BUCKET")
    topic_arn = get_env("SNS_TOPIC_ARN")

    payment_ref = f"PAY-{order_id}-{int(datetime.now(timezone.utc).timestamp())}"
    invoice_payload = build_invoice_payload(
        order_id=order_id,
        payment_ref=payment_ref,
        customer_email=customer_email,
        items=items,
        total=total,
    )
    invoice_key = build_invoice_s3_key(order_id=order_id, payment_ref=payment_ref)

    conn = None
    try:
        conn = get_db_connection()
        put_invoice_to_s3(bucket_name=bucket_name, key=invoice_key, invoice_payload=invoice_payload)
        update_order_in_rds(
            conn=conn,
            order_id=order_id,
            payment_ref=payment_ref,
            invoice_key=invoice_key,
        )
        write_audit_log(
            table_name=table_name,
            order_id=order_id,
            payment_ref=payment_ref,
            invoice_key=invoice_key,
        )
        publish_order_notification(
            topic_arn=topic_arn,
            order_id=order_id,
            customer_email=customer_email,
            total=total,
        )
    finally:
        if conn is not None:
            conn.close()

    return {
        "order_id": order_id,
        "payment_ref": payment_ref,
        "invoice_key": invoice_key,
        "status": "COMPLETED",
    }


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    logger.info("Received event: %s", json.dumps(event, default=_json_default))

    processed: List[Dict[str, Any]] = []

    for record in event.get("Records", []):
        try:
            body = json.loads(record["body"])
            result = process_order_message(body)
            processed.append(result)
            logger.info("Processed order successfully: %s", result["order_id"])
        except Exception as exc:
            logger.exception("Failed processing SQS record. It will be retried. Error: %s", str(exc))
            raise

    return {
        "message": "Processing complete",
        "processed_count": len(processed),
        "processed_orders": processed,
    }