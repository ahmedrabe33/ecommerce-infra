output "karpenter_role_arn"        { value = aws_iam_role.karpenter_controller.arn }
output "karpenter_node_role_arn"   { value = aws_iam_role.karpenter_node.arn }
output "karpenter_node_role_name"  { value = aws_iam_role.karpenter_node.name }
output "sqs_queue_name"            { value = aws_sqs_queue.interruption.name }
output "sqs_queue_url"             { value = aws_sqs_queue.interruption.url }
