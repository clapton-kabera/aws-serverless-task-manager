#----------------------------------------------------------------------------------------------------
# sns.tf
# author: Kabera Clapton
#
# description: One SNS topic for all task notifications. Each person subscribes with an email
#              subscription and a FILTER POLICY (created by scripts/admin_setup.sh), so SNS delivers
#              each message only to the people it is meant for instead of every subscriber.
#----------------------------------------------------------------------------------------------------

resource "aws_sns_topic" "task_notifications" {
  name = "${local.name_prefix}-task-notifications"

  # Encrypt messages at rest with the AWS-managed SNS key.
  kms_master_key_id = "alias/aws/sns"
}
