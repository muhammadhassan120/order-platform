import json
import os
import logging
from datetime import datetime, timezone

import boto3
import pg8000.dbapi


logger = logging.getLogger()
logger.setLevel(logging.INFO)

REGION = os.environ.get("AWS_REGION", "us-east-2")

ses_client = boto3.client("ses", region_name=REGION)
sns_client = boto3.client("sns", region_name=REGION)
s3_client = boto3.client("s3", region_name=REGION)
secrets_client = boto3.client("secretsmanager", region_name=REGION)
dynamodb = boto3.resource("dynamodb", region_name=REGION)


def get_db_connection():
    resp = secrets_client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
    secret = json.loads(resp["SecretString"])

    conn = pg8000.dbapi.connect(
        host=os.environ.get("DB_HOST", secret.get("host", "")),
        port=int(os.environ.get("DB_PORT", secret.get("port", 5432))),
        database=os.environ.get("DB_NAME", secret.get("dbname", "mydb")),
        user=secret["username"],
        password=secret["password"],
        ssl_context=True,
    )
    conn.autocommit = False
    return conn


def build_invoice_text(order_id, customer_email, items, total, payment_ref):
    lines = [
        "===========================",
        "        ORDER INVOICE      ",
        "===========================",
        f"Order ID    : {order_id}",
        f"Customer    : {customer_email}",
        f"Payment Ref : {payment_ref}",
        f"Total       : {total}",
        f"Date        : {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC",
        f"Status      : COMPLETED",
        "---------------------------",
        "Items:",
    ]

    for item in items:
        lines.append(
            f"  - Product: {item.get('product_id', '?')}  Qty: {item.get('qty', '?')}"
        )

    lines.append("===========================")
    return "\n".join(lines)


def build_invoice_html(order_id, customer_email, items, total, payment_ref):
    rows = "".join(
        f"<tr><td style='padding:6px;border:1px solid #ddd'>{i.get('product_id','?')}</td>"
        f"<td style='padding:6px;border:1px solid #ddd'>{i.get('qty','?')}</td></tr>"
        for i in items
    )

    return f"""
    <html>
      <body style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto">
        <h2 style="color:#2e7d32">Order #{order_id} — Confirmed ✅</h2>
        <p>Dear Customer,</p>
        <p>Your order has been <strong>successfully processed</strong>.</p>

        <p><strong>Customer:</strong> {customer_email}</p>
        <p><strong>Payment Ref:</strong> {payment_ref}</p>
        <p><strong>Total:</strong> {total}</p>

        <table style="border-collapse:collapse;width:100%">
          <tr style="background:#f5f5f5">
            <th style="padding:8px;border:1px solid #ddd;text-align:left">Product ID</th>
            <th style="padding:8px;border:1px solid #ddd;text-align:left">Qty</th>
          </tr>
          {rows}
        </table>

        <br>
        <p>Thank you for your order 🎉</p>
        <p><em>Order Platform</em></p>
      </body>
    </html>
    """


def handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    for record in event.get("Records", []):
        conn = None
        cursor = None

        try:
            body = json.loads(record["body"])
            order_id = body.get("order_id")

            if not order_id:
                logger.error("Missing order_id in message: %s", body)
                continue

            logger.info("Processing order_id=%s", order_id)

            conn = get_db_connection()
            cursor = conn.cursor()

            cursor.execute(
                "SELECT id, customer_email, status FROM orders WHERE id = %s",
                (order_id,),
            )
            row = cursor.fetchone()

            if not row:
                raise ValueError(f"Order {order_id} not found in database")

            order_id_db, customer_email, current_status = row
            logger.info(
                "order_id=%s customer_email=%s status=%s",
                order_id_db,
                customer_email,
                current_status,
            )

            # Use items from SQS body directly
            items = body.get("items", [])
            total = body.get("total", "0.00")

            payment_ref = f"PAY-{order_id}-{int(datetime.now(timezone.utc).timestamp())}"
            invoice_key = f"invoices/{order_id}/{payment_ref}.txt"

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

            logger.info("Order %s marked COMPLETED", order_id)

            audit_table = dynamodb.Table(os.environ["AUDIT_TABLE"])
            audit_table.put_item(
                Item={
                    "order_id": str(order_id),
                    "event": "ORDER_COMPLETED",
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "customer_email": customer_email,
                    "payment_ref": payment_ref,
                    "invoice_key": invoice_key,
                    "total": str(total),
                }
            )
            logger.info("Audit record written for order %s", order_id)

            invoice_text = build_invoice_text(
                order_id=order_id,
                customer_email=customer_email,
                items=items,
                total=total,
                payment_ref=payment_ref,
            )

            s3_client.put_object(
                Bucket=os.environ["INVOICE_BUCKET"],
                Key=invoice_key,
                Body=invoice_text.encode("utf-8"),
                ContentType="text/plain",
            )
            logger.info("Invoice stored in S3 for order %s", order_id)

            from_email = os.environ.get("SES_FROM_EMAIL", "")
            if not from_email:
                logger.warning("SES_FROM_EMAIL not set — skipping customer email")
            elif not customer_email:
                logger.warning("customer_email is empty for order %s", order_id)
            else:
                ses_client.send_email(
                    Source=from_email,
                    Destination={"ToAddresses": [customer_email]},
                    Message={
                        "Subject": {
                            "Data": f"Your Order #{order_id} is Confirmed! ✅",
                            "Charset": "UTF-8",
                        },
                        "Body": {
                            "Text": {
                                "Data": invoice_text,
                                "Charset": "UTF-8",
                            },
                            "Html": {
                                "Data": build_invoice_html(
                                    order_id=order_id,
                                    customer_email=customer_email,
                                    items=items,
                                    total=total,
                                    payment_ref=payment_ref,
                                ),
                                "Charset": "UTF-8",
                            },
                        },
                    },
                )
                logger.info(
                    "SES email sent to customer=%s for order=%s",
                    customer_email,
                    order_id,
                )

            ops_topic = os.environ.get("OPS_ALERT_TOPIC", "")
            if ops_topic:
                sns_client.publish(
                    TopicArn=ops_topic,
                    Subject=f"[OrderPlatform] Order #{order_id} Processed",
                    Message=(
                        f"Order #{order_id} for customer {customer_email} "
                        f"processed at {datetime.now(timezone.utc).isoformat()} UTC."
                    ),
                )
                logger.info("Ops-alert published to SNS for order %s", order_id)

            logger.info("order_id=%s fully processed ✅", order_id)

        except Exception as exc:
            logger.exception("Failed to process record: %s", exc)
            if conn:
                try:
                    conn.rollback()
                except Exception:
                    pass
            raise

        finally:
            try:
                if cursor:
                    cursor.close()
            except Exception:
                pass

            try:
                if conn:
                    conn.close()
            except Exception:
                pass