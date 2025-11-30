resource "aws_s3_bucket" "incoming" {
  bucket = "${var.project_name}-incoming"
}

resource "aws_s3_bucket" "processed" {
  bucket = "${var.project_name}-processed"
}


resource "aws_sns_topic" "file_events" {
  name = "${var.project_name}-file-events"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.file_events.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_sqs_queue" "processing" {
  name                      = "${var.project_name}-processing-queue"
  visibility_timeout_seconds = 60
}

resource "aws_sns_topic_subscription" "sqs" {
  topic_arn = aws_sns_topic.file_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.processing.arn
}

resource "aws_sqs_queue_policy" "sns_to_sqs" {
  queue_url = aws_sqs_queue.processing.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.processing.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.file_events.arn
          }
        }
      }
    ]
  })
}


resource "aws_iam_role" "ingestion_lambda_role" {
  name = "${var.project_name}-ingestion-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ingestion_lambda_policy" {
  name = "${var.project_name}-ingestion-lambda-policy"
  role = aws_iam_role.ingestion_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish",
          "s3:GetObject"
        ]
        Resource = "*"
      }
    ]
  })
}


resource "aws_iam_role" "sqs_consumer_lambda_role" {
  name = "${var.project_name}-sqs-consumer-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sqs_consumer_lambda_policy" {
  name = "${var.project_name}-sqs-consumer-lambda-policy"
  role = aws_iam_role.sqs_consumer_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.processing.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.processed.arn}/*"
      }
    ]
  })
}





resource "aws_lambda_function" "ingestion" {
  function_name = "${var.project_name}-ingestion"
  role          = aws_iam_role.ingestion_lambda_role.arn
  handler       = "handler.handler"
  runtime       = "python3.11"

  filename         = "${path.module}/../lambda/ingestion.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/ingestion.zip")

  environment {
    variables = {
      TOPIC_ARN = aws_sns_topic.file_events.arn
    }
  }
}

resource "aws_lambda_function" "sqs_consumer" {
  function_name = "${var.project_name}-sqs-consumer"
  role          = aws_iam_role.sqs_consumer_lambda_role.arn
  handler       = "handler.handler"
  runtime       = "python3.11"

  filename         = "${path.module}/../lambda/sqs_consumer.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/sqs_consumer.zip")

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.processed.bucket
    }
  }
}



resource "aws_lambda_permission" "allow_s3_to_invoke_ingestion" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.incoming.arn
}

resource "aws_s3_bucket_notification" "incoming_notification" {
  bucket = aws_s3_bucket.incoming.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingestion.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3_to_invoke_ingestion]
}


resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn  = aws_sqs_queue.processing.arn
  function_name     = aws_lambda_function.sqs_consumer.arn
  batch_size        = 10
  enabled           = true
}
