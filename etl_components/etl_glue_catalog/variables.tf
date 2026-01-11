variable "database_name" {
  description = "Glue database name"
  type        = string
}

variable "crawler_name" {
  description = "Glue crawler name"
  type        = string
}

variable "table_prefix" {
  description = "Prefix prepended to tables created by the crawler"
  type        = string
}

variable "curated_bucket_name" {
  description = "S3 bucket containing curated Parquet data"
  type        = string
}

variable "curated_prefix" {
  description = "S3 prefix under curated bucket to crawl"
  type        = string
}

variable "glue_role_arn" {
  description = "IAM role assumed by Glue crawler"
  type        = string
}