variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "bucket_type" {
  description = "Purpose of the bucket: raw | curated | athena-results"
  type        = string

  validation {
    condition     = contains(["raw", "curated", "athena-results"], var.bucket_type)
    error_message = "bucket_type must be one of: raw, curated, athena-results"
  }
}

variable "enable_versioning" {
  description = "Enable versioning (true for raw buckets)"
  type        = bool
  default     = false
}