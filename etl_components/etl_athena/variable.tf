variable "workgroup_name" {
  description = "Athena workgroup name"
  type        = string
}

variable "results_bucket_name" {
  description = "S3 bucket for Athena query results"
  type        = string
}

variable "results_prefix" {
  description = "Prefix under the results bucket"
  type        = string
}

variable "enforce_workgroup_configuration" {
  description = "Force queries to obey workgroup settings"
  type        = bool
  default     = true
}

variable "bytes_scanned_cutoff_per_query" {
  description = "Bytes scanned limit per query (null = no limit)"
  type        = number
  default     = null
}