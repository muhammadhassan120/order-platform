resource "aws_sns_topic" "order_notifications" {
  name = "${var.name_prefix}-order-notifications"
}

resource "aws_sns_topic" "ops_alerts" {
  name = "${var.name_prefix}-ops-alerts"
}