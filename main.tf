# S3 BUCKETS
module "raw_bucket" {
  source            = "./etl_components/etl_s3_bucket"
  bucket_name       = "${var.project_name}-raw"
  bucket_type       = "raw"
  enable_versioning = true
}

module "curated_bucket" {
  source      = "./etl_components/etl_s3_bucket"
  bucket_name = "${var.project_name}-curated"
  bucket_type = "curated"
}

module "athena_results_bucket" {
  source      = "./etl_components/etl_s3_bucket"
  bucket_name = "${var.project_name}-athena-results"
  bucket_type = "athena-results"
}


# IAM (Execution Boundaries)
module "iam" {
    source = "./etl_components/etl_iam"
    raw_bucket_arn = module.raw_bucket.bucket_arn 
    curated_bucket_arn = module.curated_bucket.bucket_arn
    athena_results_bucket_arn = module.athena_results_bucket.bucket_arn
}

# ETL Lambda
module "etl_lambda" {
    source = "./etl_components/etl_lambda"
    lambda_name   = "${var.project_name}-etl"
    role_arn      = module.iam.lambda_role_arn
    handler       = "flatten.lambda_handler"
    package_path  = "etl.zip"

    raw_bucket_name     = module.raw_bucket.bucket_name
    curated_bucket_name = module.curated_bucket.bucket_name
    curated_prefix      = "dataset/schema=${var.schema_version}/"
    schema_version      = var.schema_version
}


# S3 -> Lambda notification
resource "aws_lambda_permission" "allow_raw_bucket" {
  statement_id  = "AllowRawBucketInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.etl_lambda.lambda_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.raw_bucket.bucket_arn
}

resource "aws_s3_bucket_notification" "raw_to_lambda" {
    bucket = module.raw_bucket.bucket_name
    
    lambda_function {
      lambda_function_arn = module.etl_lambda.lambda_arn
      events = ["s3:ObjectCreated:*"]
      filter_prefix = ""
        filter_suffix = ".json"
    }

    depends_on = [ 
        aws_lambda_permission.allow_raw_bucket
     ]
}

# GLUE
module "glue_catalog" {
    source = "./etl_components/etl_glue_catalog"

  database_name       = "${var.project_name}_db"
  crawler_name        = "${var.project_name}_crawler"
  table_prefix        = "dataset_"
  curated_bucket_name = module.curated_bucket.bucket_name
  curated_prefix      = "dataset/schema=${var.schema_version}/"
  glue_role_arn       = module.iam.glue_role_arn
}


# ATHENA (query boundary)
module "athena" {
  source = "./etl_components/etl_athena"

  workgroup_name       = "${var.project_name}_wg"
  results_bucket_name = module.athena_results_bucket.bucket_name
  results_prefix      = "results/"
}