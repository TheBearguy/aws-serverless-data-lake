resource "aws_cloudwatch_log_group" "this" {
    name = "/aws/lambda/${var.lambda_name}"
    retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "this" {
    function_name = var.lambda_name
    role = var.role_arn
    handler = var.handler
    runtime = var.runtime
    timeout = var.timeout
    memory_size = var.memory_size

    filename = var.package_path
    source_code_hash = filebase64sha256(var.package_path)

    environment {
        variables = {
            RAW_BUCKET      = var.raw_bucket_name
            CURATED_BUCKET  = var.curated_bucket_name
            CURATED_PREFIX  = var.curated_prefix
            SCHEMA_VERSION  = var.schema_version
        }
    }
    depends_on = [
        aws_cloudwatch_log_group.this
    ]  
}

resource "aws_lambda_permission" "allow_s3_invoke" {
    statement_id = "AllowExecutionFromS3"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.this.function_name
    principal = "s3.amazonaws.com"
}

