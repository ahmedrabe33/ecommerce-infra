# Karpenter: IAM role, SQS interruption queue, EventBridge rules

data "aws_iam_policy_document" "karpenter_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.cluster_name}-karpenter-controller-role"
  assume_role_policy = data.aws_iam_policy_document.karpenter_assume.json
  tags               = { Name = "${var.cluster_name}-karpenter-controller-role" }
}

resource "aws_iam_policy" "karpenter_controller" {
  name = "${var.cluster_name}-karpenter-controller-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate", "ec2:CreateFleet", "ec2:RunInstances",
          "ec2:CreateTags", "ec2:TerminateInstances", "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates", "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes", "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones", "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.karpenter_node.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage","sqs:GetQueueAttributes","sqs:GetQueueUrl","sqs:ReceiveMessage"]
        Resource = aws_sqs_queue.interruption.arn
      },
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${var.region}:${var.account_id}:cluster/${var.cluster_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile", "iam:TagInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile", "iam:GetInstanceProfile"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# Karpenter Node IAM Role — nodes provisioned by Karpenter use this role to join EKS
resource "aws_iam_role" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "node_cni" {
  role = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "node_ecr" {
  role = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "node_ssm" {
  role = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# SQS queue for Spot interruption notifications
# When AWS reclaims a Spot node it sends a 2-minute warning.
# Karpenter reads this queue and gracefully migrates pods.
resource "aws_sqs_queue" "interruption" {
  name                      = "${var.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300
  tags                      = { Name = "${var.cluster_name}-karpenter-interruption" }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.interruption.arn
    }]
  })
}

# EventBridge rules send EC2 events to the SQS queue
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name          = "${var.cluster_name}-spot-interruption"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    "detail-type" = ["EC2 Spot Instance Interruption Warning"]
  })
}
resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_rule" "instance_rebalance" {
  name          = "${var.cluster_name}-instance-rebalance"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    "detail-type" = ["EC2 Instance Rebalance Recommendation"]
  })
}
resource "aws_cloudwatch_event_target" "instance_rebalance" {
  rule      = aws_cloudwatch_event_rule.instance_rebalance.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}

resource "aws_cloudwatch_event_rule" "instance_state" {
  name          = "${var.cluster_name}-instance-state"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
  })
}
resource "aws_cloudwatch_event_target" "instance_state" {
  rule      = aws_cloudwatch_event_rule.instance_state.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}
