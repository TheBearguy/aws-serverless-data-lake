Steps: 
1. Json data -> S3 (event trigger)
2. flatten that json and convert in parquet -  using aws lambda
3. store parquet format in s3 (event trigger) [Datalake]
4. AWS Glue Crawler -> data catalog (metadata)
5. query the data in the glue crawler using - aws athena 

Terraform steps: 
1. S3 - module
2. lambda.tf, glue_crawler.tf, athena.tf
3. first s3 will be configured to lambda
4. second s3 will be configured to glue_crawler


1. upload json on s3 -> user_data

future: 
foundation.tfstate  (s3, iam)
ingestion.tfstate   (lambda + notifications)
catalog.tfstate     (glue)
query.tfstate       (athena)
