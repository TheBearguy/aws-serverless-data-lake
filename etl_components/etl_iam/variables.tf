variable "raw_bucket_arn" {
  type        = string
  description = "ARN of the raw JSON S3 bucket"
}

variable "curated_bucket_arn" {
  type        = string
  description = "ARN of the curated Parquet S3 bucket"
}

variable "athena_results_bucket_arn" {
  type        = string
  description = "ARN of the Athena results bucket"
}