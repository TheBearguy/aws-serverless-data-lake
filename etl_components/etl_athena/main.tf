resource "aws_athena_workgroup" "this" {
    name = var.workgroup_name
    configuration {
      enforce_workgroup_configuration = var.enforce_workgroup_configuration
      result_configuration {
            output_location = "s3://${var.results_bucket_name}/${var.results_prefix}"
      }
      bytes_scanned_cutoff_per_query = var.bytes_scanned_cutoff_per_query
    }
}