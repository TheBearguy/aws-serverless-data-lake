# ETL Lambda Module

This module provisions a single-purpose Lambda function that transforms
raw JSON objects into Parquet files under a fixed schema version.

## Responsibilities
- Lambda function
- CloudWatch log group
- Invocation permission (S3)

## Out of Scope
- S3 bucket creation
- S3 notifications
- Glue catalog
- Athena resources
- Schema discovery or evolution