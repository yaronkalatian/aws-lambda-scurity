terraform {
required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-north-1"
}

# Create an SNS Topic for Alerts
resource "aws_sns_topic" "security_alerts" {
  name = "SecurityAlerts"
}

# Create subscription by email for SNS topic
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = "shaulk10@gmail.com"  # Replace with actual email
}

# Create an IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "LambdaExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

#  Attach IAM Policies to Lambda Role
resource "aws_iam_policy" "lambda_logging" {
  name        = "LambdaLogging"
  description = "Allows Lambda to write logs to CloudWatch"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
      Effect = "Allow",
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_iam_role_policy_attachment" "lambda_sns" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}


# Create  Lambda Function "SecurityMonitoring"
resource "aws_lambda_function" "security_monitoring" {
  function_name    = "SecurityMonitoring"
  role            = aws_iam_role.lambda_exec.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  filename        = "lambda.zip"  # Ensure this is packaged before deployment
  source_code_hash = filebase64sha256("lambda.zip")
  
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_alerts.arn
    }
  }
}

resource "aws_sns_topic_subscription" "lambda_subscription" {
    topic_arn = aws_sns_topic.security_alerts.arn
    protocol  = "lambda"
    endpoint  = aws_lambda_function.security_monitoring.arn
  }
  
resource "aws_lambda_function_event_invoke_config" "security_monitoring_dest" {
  function_name                = aws_lambda_function.security_monitoring.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 60

  destination_config {
    on_success {
      destination = aws_sns_topic.security_alerts.arn
    }
    on_failure {
      destination = aws_sns_topic.security_alerts.arn
    }
  }
}

# Create CloudWatch EventBridge Rule for IAM create user and create access key
resource "aws_cloudwatch_event_rule" "iam_user_creation" {
  name        = "IAMUserCreation"
  description = "Triggers on IAM user creation"
  event_pattern = jsonencode({
    source = ["aws.iam"],
    detail-type = ["AWS API Call via CloudTrail"],
    detail = {
      eventName = ["CreateUser", "CreateAccessKey"]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda_iam_user_creation" {
  rule      = aws_cloudwatch_event_rule.iam_user_creation.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.security_monitoring.arn
}

# Lambda Permissions to Invoke Lambda
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_monitoring.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.iam_user_creation.arn
}


# EventBridge Rule for CloudTrail Events (S3 Policy Changes)
resource "aws_cloudwatch_event_rule" "s3_policy_changes" {
  name        = "S3BucketPolicyChanges"
  description = "Triggers when an S3 bucket policy is modified"

  event_pattern = jsonencode({
    source      = ["aws.s3"],
    detail-type = ["AWS API Call via CloudTrail"],
    detail = {
      eventName = ["PutBucketPolicy"]
    }
  })
}

# EventBridge Rule Target (Lambda)
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.s3_policy_changes.name
  arn       = aws_lambda_function.security_monitoring.arn
}

# Lambda Permissions for EventBridge to Invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_monitoring.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_policy_changes.arn
}


# CloudWatch EventBridge Rule for Security Group Ingress Rule Changes
resource "aws_cloudwatch_event_rule" "sg_ingress_rule" {
  name        = "sg-ingress-rule"
  description = "Triggers when a security group allows ingress from a public IP"
  event_pattern = jsonencode({
    source      = ["aws.ec2"],
    detail-type = ["AWS API Call via CloudTrail"],
    detail = {
      eventSource = ["ec2.amazonaws.com"],
      eventName   = ["AuthorizeSecurityGroupIngress"],
      requestParameters = {
        ipPermissions = {
          items = {
            ipRanges = {
              items = {
                cidrIp = [{
                  "anything-but": [
                    "10.0.0.0/8",
                    "172.16.0.0/12",
                    "192.168.0.0/16"
                  ]
                }]
              }
            }
          }
        }
      }
    }
  })
}

# Attach Event Rule to Lambda
resource "aws_cloudwatch_event_target" "sg_event_target" {
  rule      = aws_cloudwatch_event_rule.sg_ingress_rule.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.security_monitoring.arn
}

# Allow EventBridge to Invoke Lambda
resource "aws_lambda_permission" "sg_ingress_rule" {
  statement_id  = "EventBridgeSgIngressRule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_monitoring.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sg_ingress_rule.arn
}
