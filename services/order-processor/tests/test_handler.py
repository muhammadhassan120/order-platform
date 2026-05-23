import importlib
import json
import os
import sys
import types
from pathlib import Path
from unittest.mock import Mock


os.environ.setdefault("AWS_EC2_METADATA_DISABLED", "true")
os.environ.setdefault("AWS_REGION", "us-east-2")
os.environ.setdefault("DB_SECRET_ARN", "secret-arn")
os.environ.setdefault("AUDIT_TABLE", "audit-table")
os.environ.setdefault("INVOICE_BUCKET", "invoice-bucket")
os.environ.setdefault("SES_FROM_EMAIL", "sender@example.com")
os.environ.setdefault("OPS_ALERT_TOPIC", "ops-topic")


def install_fake_dependencies():
    boto3_module = types.ModuleType("boto3")
    boto3_module.client = lambda *args, **kwargs: Mock()
    boto3_module.resource = lambda *args, **kwargs: Mock(Table=lambda name: Mock())
    sys.modules["boto3"] = boto3_module

    pg8000_module = types.ModuleType("pg8000")
    dbapi_module = types.ModuleType("pg8000.dbapi")
    dbapi_module.connect = Mock()
    pg8000_module.dbapi = dbapi_module
    sys.modules["pg8000"] = pg8000_module
    sys.modules["pg8000.dbapi"] = dbapi_module


install_fake_dependencies()

SERVICE_DIR = Path(__file__).resolve().parents[1]
if str(SERVICE_DIR) not in sys.path:
    sys.path.insert(0, str(SERVICE_DIR))

processor = importlib.import_module("handler")


class FakeCursor:
    def __init__(self, row):
        self.row = row
        self.executed = []
        self.closed = False

    def execute(self, sql, params=None):
        self.executed.append((sql, params))

    def fetchone(self):
        return self.row

    def close(self):
        self.closed = True


class FakeConnection:
    def __init__(self, cursor):
        self._cursor = cursor
        self.commit = Mock()
        self.rollback = Mock()
        self.closed = False

    def cursor(self):
        return self._cursor

    def close(self):
        self.closed = True


def sqs_event(order_id=7):
    return {
        "Records": [
            {
                "body": json.dumps(
                    {
                        "order_id": order_id,
                        "customer_email": "customer@example.com",
                        "items": [{"product_id": "SMOKE-001", "qty": 1}],
                        "total": "0.01",
                    }
                )
            }
        ]
    }


def test_completed_order_is_skipped(monkeypatch):
    cursor = FakeCursor((7, "customer@example.com", "COMPLETED"))
    conn = FakeConnection(cursor)
    monkeypatch.setattr(processor, "get_db_connection", lambda: conn)
    processor.s3_client = Mock()
    processor.ses_client = Mock()
    processor.sns_client = Mock()

    processor.handler(sqs_event(), None)

    assert len(cursor.executed) == 1
    assert "SELECT id, customer_email, status" in cursor.executed[0][0]
    assert conn.commit.call_count == 1
    assert processor.s3_client.put_object.call_count == 0
    assert processor.ses_client.send_email.call_count == 0
    assert processor.sns_client.publish.call_count == 0


def test_payment_reference_and_invoice_key_are_deterministic():
    assert processor.build_payment_ref(7) == "PAY-7"
    assert processor.build_invoice_key(7, "PAY-7") == "invoices/7/PAY-7.txt"


def test_notification_failures_do_not_retry_completed_order(monkeypatch):
    cursor = FakeCursor((7, "customer@example.com", "PENDING"))
    conn = FakeConnection(cursor)
    audit_table = Mock()
    dynamodb = Mock(Table=Mock(return_value=audit_table))

    monkeypatch.setattr(processor, "get_db_connection", lambda: conn)
    processor.dynamodb = dynamodb
    processor.s3_client = Mock()
    processor.ses_client = Mock()
    processor.sns_client = Mock()
    processor.ses_client.send_email.side_effect = RuntimeError("ses down")
    processor.sns_client.publish.side_effect = RuntimeError("sns down")

    processor.handler(sqs_event(), None)

    assert conn.rollback.call_count == 0
    assert conn.commit.call_count == 2
    assert processor.s3_client.put_object.call_args.kwargs["Key"] == "invoices/7/PAY-7.txt"
    final_update = cursor.executed[-1]
    assert "SET status = %s" in final_update[0]
    assert final_update[1] == ("COMPLETED", "PAY-7", "invoices/7/PAY-7.txt", 7)
    assert audit_table.put_item.call_count == 1
    assert processor.ses_client.send_email.call_count == 1
    assert processor.sns_client.publish.call_count == 1
