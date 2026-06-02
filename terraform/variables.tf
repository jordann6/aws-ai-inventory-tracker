variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment label (dev / prod)."
  type        = string
  default     = "dev"
}

variable "bedrock_model_id" {
  description = "Bedrock foundation model ID used for inventory analysis."
  type        = string
  default     = "anthropic.claude-3-5-haiku-20241022-v1:0"
}
