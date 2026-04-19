import json
import os
import uuid
from datetime import datetime

import boto3
import psycopg2

dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")
s3 = boto3.client("s3")
ses = boto3.client("sesv2")
sm = boto3.client("secretsmanager")

AUDIT_TABLE = os.environ["AUDIT_TABLE"]
SNS_TOPIC = os.environ["SNS_TOPIC_ARN"]
BUCKET = os.environ["INVOICE_BUCKET"]
DB_SECRET_ARN = os.environ["DB_SECRET_ARN"]
OPS_ALERT_TOPIC = os.environ["OPS_ALERT_TOPIC"]
SES_FROM_EMAIL = os.environ["SES_FROM_EMAIL"]


def get_db_connection():
    secret = sm.get_secret_value(SecretId=DB_SECRET_ARN)
    creds = json.loads(secret["SecretString"])
    return psycopg2.connect(
        host=creds["host"],
        port=creds["port"],
        dbname=creds["dbname"],
        user=creds["username"],
        password=creds["password"],
        sslmode="require",
    )


def send_customer_email(customer_email, order_id, total, payment_ref, invoice_key):
    subject = f"Order {order_id} confirmed"

    text_body = f"""Hello,

Your order has been confirmed.

Order ID: {order_id}
Payment Ref: {payment_ref}
Total: ${total}
Invoice File: {invoice_key}

Thank you for your order.
"""

    html_body = f"""
    <html>
      <body>
        <h2>Order Confirmed</h2>
        <p>Your order has been confirmed.</p>
        <ul>
          <li><strong>Order ID:</strong> {order_id}</li>
          <li><strong>Payment Ref:</strong> {payment_ref}</li>
          <li><strong>Total:</strong> ${total}</li>
          <li><strong>Invoice File:</strong> {invoice_key}</li>
        </ul>
        <p>Thank you for your order.</p>
      </body>
    </html>
    """

    ses.send_email(
        FromEmailAddress=SES_FROM_EMAIL,
        Destination={"ToAddresses": [customer_email]},
        Content={
            "Simple": {
                "Subject": {"Data": subject},
                "Body": {
                    "Text": {"Data": text_body},
                    "Html": {"Data": html_body},
                },
            }
        },
    )


def publish_internal_fanout(order_id, customer_email, total, payment_ref, invoice_key):
    sns.publish(
        TopicArn=SNS_TOPIC,
        Subject=f"ORDER_COMPLETED {order_id}",
        Message=json.dumps(
            {
                "event_type": "ORDER_COMPLETED",
                "order_id": order_id,
                "customer_email": customer_email,
                "payment_ref": payment_ref,
                "total": str(total),
                "invoice_key": invoice_key,
                "processed_at": datetime.utcnow().isoformat(),
            }
        ),
        MessageAttributes={
            "event_type": {
                "DataType": "String",
                "StringValue": "ORDER_COMPLETED",
            }
        },
    )


def handler(event, context):
    """
    Triggered by SQS for each order message:
    1. Simulate payment processing
    2. Generate invoice in S3
    3. Update order status in RDS
    4. Write audit event to DynamoDB
    5. Publish internal fanout event to SNS
    6. Send customer email through SES
    """
    for record in event["Records"]:
        body = json.loads(record["body"])
        order_id = body["order_id"]

        print(f"Processing order {order_id}")

        try:
            payment_ref = f"PAY-{uuid.uuid4().hex[:12].upper()}"

            invoice_key = f"invoices/order_{order_id}/{payment_ref}.json"
            invoice = {
                "order_id": order_id,
                "payment_ref": payment_ref,
                "customer": body["customer_email"],
                "items": body["items"],
                "total": str(body["total"]),
                "issued_at": datetime.utcnow().isoformat(),
            }

            s3.put_object(
                Bucket=BUCKET,
                Key=invoice_key,
                Body=json.dumps(invoice, indent=2),
                ContentType="application/json",
                ServerSideEncryption="aws:kms",
            )

            conn = get_db_connection()
            try:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        UPDATE orders
                        SET status = 'COMPLETED',
                            payment_ref = %s,
                            invoice_key = %s,
                            processed_at = NOW()
                        WHERE id = %s
                        """,
                        (payment_ref, invoice_key, order_id),
                    )
                conn.commit()
            finally:
                conn.close()

            table = dynamodb.Table(AUDIT_TABLE)
            table.put_item(
                Item={
                    "PK": f"ORDER#{order_id}",
                    "SK": f"EVENT#{datetime.utcnow().isoformat()}",
                    "event_type": "ORDER_COMPLETED",
                    "payment_ref": payment_ref,
                    "invoice_key": invoice_key,
                    "ttl": int(datetime.utcnow().timestamp()) + (90 * 86400),
                }
            )

            publish_internal_fanout(
                order_id=order_id,
                customer_email=body["customer_email"],
                total=body["total"],
                payment_ref=payment_ref,
                invoice_key=invoice_key,
            )

            send_customer_email(
                customer_email=body["customer_email"],
                order_id=order_id,
                total=body["total"],
                payment_ref=payment_ref,
                invoice_key=invoice_key,
            )

            print(f"Order {order_id} processed successfully")

        except Exception as e:
            print(f"FAILED processing order {order_id}: {e}")
            raise


def dlq_handler(event, context):
    """
    Handles messages that failed 3 times.
    Sends ops alert through SNS.
    """
    for record in event["Records"]:
        body = json.loads(record["body"])
        print(f"DLQ: Order {body.get('order_id')} permanently failed")

        sns.publish(
            TopicArn=OPS_ALERT_TOPIC,
            Subject="ORDER PROCESSING FAILURE",
            Message=(
                f"Order {body.get('order_id')} failed after retries.\n\n"
                f"Payload:\n{json.dumps(body, indent=2)}"
            ),
        )