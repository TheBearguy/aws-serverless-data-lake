variable "lambda_name" {
    description = "Name of the ETL lambda function"
    type = string
}

variable "role_arn" {
    description = "IAM role ARN assumed by the Lambda"
    type        = string
}

variable "handler" {
    description = "Lambda handler"
    type = string
}

variable "runtime" {
    description = "Lambda runtime"
    type = string
    default = "python3.11"
}

variable "timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 300
}

variable "memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 1024
}

variable "package_path" {
    description = "Path to lambda deployment package (zip)"
    type = string
}

variable "raw_bucket_name" {
    description = "S3 bucket containing raw JSON data"
    type = string
}

variable "curated_bucket_name" {
    description = "S3 bucket containing curated Parquet output data"
    type = string
}

variable "curated_prefix" {
  description = "Prefix under curated bucket where Parquet is written"
  type        = string
}

variable "schema_version" {
  description = "Schema version used by this Lambda"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}