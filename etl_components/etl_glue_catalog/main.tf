resource "aws_glue_catalog_database" "this" {
    name = var.database_name
}

resource "aws_glue_crawler" "this" {
    name          = var.crawler_name
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.this.name
  table_prefix  = var.table_prefix

  s3_target {
        path = "s3://${var.curated_bucket_name}/${var.curated_prefix}"
  }

  schema_change_policy {
    update_behavior = "LOG"
    delete_behavior = "LOG"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }
}