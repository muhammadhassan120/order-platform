import json
import os
import logging
import ssl
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


def build_db_ssl_context():
    return ssl.create_default_context()


def get_db_connection():
    resp = secrets_client.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
    secret = json.loads(resp["SecretString"])

    conn = pg8000.dbapi.connect(
        host=os.environ.get("DB_HOST", secret.get("host", "")),
        port=int(os.environ.get("DB_PORT", secret.get("port", 5432))),
        database=os.environ.get("DB_NAME", secret.get("dbname", "mydb")),
        user=secret["username"],
        password=secret["password"],
        ssl_context=build_db_ssl_context(),
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
        "Status      : COMPLETED",
        "---------------------------",
        "Items:",
    ]

    for item in items:
        lines.append(
            f"  - Product: {item.get('product_id', '?')}  Qty: {item.get('qty', '?')}"
        )

    lines.append("===========================")
    return "\n".join(lines)


def _format_money(value):
    try:
        return f"USD {float(value):,.2f}"
    except (TypeError, ValueError):
        return f"USD {value}"


def _pdf_escape(value):
    return (
        str(value)
        .encode("latin-1", "replace")
        .decode("latin-1")
        .replace("\\", "\\\\")
        .replace("(", "\\(")
        .replace(")", "\\)")
        .replace("\r", " ")
        .replace("\n", " ")
        .replace("\t", " ")
    )


def _pdf_text(text, x, y, size=12, font="F1", color=(0.13, 0.12, 0.1)):
    r, g, b = color
    return f"BT {r:.3f} {g:.3f} {b:.3f} rg /{font} {size} Tf {x} {y} Td ({_pdf_escape(text)}) Tj ET"


def _pdf_rect(x, y, width, height, color):
    r, g, b = color
    return f"{r:.3f} {g:.3f} {b:.3f} rg {x} {y} {width} {height} re f"


def build_invoice_pdf(order_id, customer_email, items, total, payment_ref):
    issued_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    commands = [
        _pdf_rect(0, 0, 612, 792, (1, 1, 1)),
        _pdf_rect(0, 720, 612, 72, (0.05, 0.14, 0.18)),
        _pdf_rect(0, 708, 612, 12, (0.09, 0.62, 0.42)),
        _pdf_text("ORDER INVOICE", 48, 748, 28, "F2", (1, 1, 1)),
        _pdf_text(f"Order #{order_id}", 48, 728, 13, "F1", (0.88, 0.96, 0.92)),
        _pdf_rect(448, 738, 116, 28, (0.84, 0.7, 0.42)),
        _pdf_text("COMPLETED", 466, 747, 12, "F2", (0.05, 0.14, 0.18)),
        _pdf_rect(48, 610, 516, 72, (0.96, 0.98, 0.97)),
        _pdf_rect(48, 676, 516, 6, (0.84, 0.7, 0.42)),
        _pdf_text("Customer", 68, 650, 10, "F2", (0.38, 0.42, 0.39)),
        _pdf_text(customer_email, 68, 630, 14, "F1", (0.1, 0.12, 0.12)),
        _pdf_text("Payment reference", 336, 650, 10, "F2", (0.38, 0.42, 0.39)),
        _pdf_text(payment_ref, 336, 630, 14, "F1", (0.1, 0.12, 0.12)),
        _pdf_rect(48, 532, 248, 48, (0.93, 0.97, 1.0)),
        _pdf_text("Invoice date", 68, 560, 10, "F2", (0.28, 0.39, 0.48)),
        _pdf_text(issued_at, 68, 542, 12, "F1", (0.12, 0.18, 0.22)),
        _pdf_rect(316, 532, 248, 48, (0.98, 0.94, 0.84)),
        _pdf_text("Total", 336, 560, 10, "F2", (0.46, 0.36, 0.15)),
        _pdf_text(_format_money(total), 336, 540, 18, "F2", (0.12, 0.1, 0.06)),
        _pdf_text("Items", 48, 486, 18, "F2", (0.05, 0.14, 0.18)),
        _pdf_rect(48, 454, 516, 28, (0.05, 0.14, 0.18)),
        _pdf_text("Product ID", 66, 464, 11, "F2", (1, 1, 1)),
        _pdf_text("Quantity", 442, 464, 11, "F2", (1, 1, 1)),
    ]

    row_y = 426
    for index, item in enumerate(items[:8]):
        fill = (0.98, 0.98, 0.96) if index % 2 == 0 else (0.93, 0.97, 0.96)
        commands.extend(
            [
                _pdf_rect(48, row_y - 8, 516, 30, fill),
                _pdf_text(item.get("product_id", "?"), 66, row_y, 12, "F1", (0.12, 0.12, 0.1)),
                _pdf_text(item.get("qty", "?"), 466, row_y, 12, "F2", (0.08, 0.28, 0.21)),
            ]
        )
        row_y -= 34

    if len(items) > 8:
        commands.append(
            _pdf_text(f"+ {len(items) - 8} more item(s)", 66, row_y, 11, "F1", (0.38, 0.42, 0.39))
        )

    commands.extend(
        [
            _pdf_rect(48, 72, 516, 44, (0.96, 0.98, 0.97)),
            _pdf_text("Thank you for your order.", 68, 94, 13, "F2", (0.05, 0.14, 0.18)),
            _pdf_text("Order Platform", 68, 78, 10, "F1", (0.38, 0.42, 0.39)),
        ]
    )

    content = "\n".join(commands).encode("latin-1", "replace")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>",
        b"<< /Length " + str(len(content)).encode("ascii") + b" >>\nstream\n" + content + b"\nendstream",
    ]

    pdf = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
    offsets = []

    for index, obj in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf += f"{index} 0 obj\n".encode("ascii") + obj + b"\nendobj\n"

    xref_offset = len(pdf)
    pdf += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode("ascii")

    for offset in offsets:
        pdf += f"{offset:010d} 00000 n \n".encode("ascii")

    pdf += (
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref_offset}\n%%EOF\n"
    ).encode("ascii")
    return pdf


def build_invoice_html(order_id, customer_email, items, total, payment_ref):
    rows = "".join(
        f"<tr><td style='padding:6px;border:1px solid #ddd'>{i.get('product_id','?')}</td>"
        f"<td style='padding:6px;border:1px solid #ddd'>{i.get('qty','?')}</td></tr>"
        for i in items
    )

    return f"""
    <html>
      <body style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto">
        <h2 style="color:#2e7d32">Order #{order_id} - Confirmed</h2>
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
        <p>Thank you for your order.</p>
        <p><em>Order Platform</em></p>
      </body>
    </html>
    """


def build_payment_ref(order_id):
    return f"PAY-{order_id}"


def build_invoice_key(order_id, payment_ref):
    return f"invoices/{order_id}/{payment_ref}.pdf"


def send_customer_email(order_id, customer_email, items, total, payment_ref, invoice_text):
    from_email = os.environ.get("SES_FROM_EMAIL", "")
    if not from_email:
        logger.warning("SES_FROM_EMAIL not set; skipping customer email")
        return

    if not customer_email:
        logger.warning("customer_email is empty for order %s", order_id)
        return

    try:
        ses_client.send_email(
            Source=from_email,
            Destination={"ToAddresses": [customer_email]},
            Message={
                "Subject": {
                    "Data": f"Your Order #{order_id} is Confirmed",
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
        logger.info("SES email sent to customer=%s for order=%s", customer_email, order_id)
    except Exception as exc:
        logger.warning("SES email failed for order %s: %s", order_id, exc, exc_info=True)


def publish_ops_alert(order_id, customer_email):
    ops_topic = os.environ.get("OPS_ALERT_TOPIC", "")
    if not ops_topic:
        return

    try:
        sns_client.publish(
            TopicArn=ops_topic,
            Subject=f"[OrderPlatform] Order #{order_id} Processed",
            Message=(
                f"Order #{order_id} for customer {customer_email} "
                f"processed at {datetime.now(timezone.utc).isoformat()} UTC."
            ),
        )
        logger.info("Ops-alert published to SNS for order %s", order_id)
    except Exception as exc:
        logger.warning("Ops-alert publish failed for order %s: %s", order_id, exc, exc_info=True)


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

            if current_status == "COMPLETED":
                logger.info("Order %s is already COMPLETED; skipping duplicate message", order_id)
                conn.commit()
                continue

            cursor.execute(
                """
                UPDATE orders
                SET status = %s
                WHERE id = %s
                """,
                ("PROCESSING", order_id),
            )
            conn.commit()
            logger.info("Order %s marked PROCESSING", order_id)

            items = body.get("items", [])
            total = body.get("total", "0.00")

            payment_ref = build_payment_ref(order_id)
            invoice_key = build_invoice_key(order_id, payment_ref)

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
            invoice_pdf = build_invoice_pdf(
                order_id=order_id,
                customer_email=customer_email,
                items=items,
                total=total,
                payment_ref=payment_ref,
            )

            s3_client.put_object(
                Bucket=os.environ["INVOICE_BUCKET"],
                Key=invoice_key,
                Body=invoice_pdf,
                ContentType="application/pdf",
            )
            logger.info("Invoice stored in S3 for order %s", order_id)

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

            send_customer_email(order_id, customer_email, items, total, payment_ref, invoice_text)
            publish_ops_alert(order_id, customer_email)

            logger.info("order_id=%s fully processed", order_id)

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
