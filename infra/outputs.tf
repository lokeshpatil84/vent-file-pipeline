output "incoming_bucket" {
  value = aws_s3_bucket.incoming.bucket
}

output "processed_bucket" {
  value = aws_s3_bucket.processed.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.file_events.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.processing.id
}
