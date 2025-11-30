variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "event-file-pipeline"
}

variable "notification_email" {
  description = "Email address to receive SNS notifications"
  type        = string
}