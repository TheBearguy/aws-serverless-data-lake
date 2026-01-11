resource "aws_iam_role" "lambda_role" {
    name = "etl-lambda-role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect    = "Allow"
            Principal = { Service = "lambda.amazonaws.com" }
            Action    = "sts:AssumeRole"
        }]
    })
}


resource "aws_iam_policy" "lambda_policy" {
    name = "etl-lambda-policy"
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${var.raw_bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${var.curated_bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
    })
}


resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "glue_role" {
    name = "glue-crawler-role"
    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# resource "aws_iam_policy" "glue_policy" {
#     name = "glue-crawler-policy"
#     policy = jsonencode({
#         Version = "2012-10-17"
#         Statement = [
#             {
#                 Effect = "Allow"
#                 Action = ["S3.GetObject", "S3.ListBucket"]
#                 Resource = [
#                     var.curated_bucket_arn, 
#                     "${var.curated_bucket_arn}/*"
#                 ]
#             },
#             {
#                 Effect = "Allow"
#                 Action = [
#                     "glue:GetDatabase",
#                     "glue:GetDatabases",
#                     "glue:UpdateDatabase",

#                     "glue:CreateTable",
#                     "glue:GetTable",
#                     "glue:GetTables",
#                     "glue:UpdateTable",

#                     "glue:GetCrawler",
#                     "glue:CreateCrawler",
#                     "glue:StartCrawler",
#                     "glue:UpdateCrawler"
#                 ]
#             Resource = "*"
#             }
#         ]
#     })
# }
resource "aws_iam_policy" "glue_policy" {
  name = "glue-crawler-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadCuratedData"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.curated_bucket_arn,
          "${var.curated_bucket_arn}/*"
        ]
      },
      {
        Sid    = "GlueCatalogAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:CreateDatabase",
          "glue:UpdateDatabase",

          "glue:GetTable",
          "glue:GetTables",
          "glue:CreateTable",
          "glue:UpdateTable",

          "glue:GetCrawler",
          "glue:CreateCrawler",
          "glue:UpdateCrawler",
          "glue:StartCrawler"
        ]
        Resource = "*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "glue_attach" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_policy.arn
}

resource "aws_iam_role" "athena_role" {
  name = "athena-query-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "athena.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "athena_policy" {
  name = "athena-query-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          var.curated_bucket_arn,
          "${var.curated_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${var.athena_results_bucket_arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "athena:*",
          "glue:GetTable",
          "glue:GetDatabase"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "athena_attach" {
  role       = aws_iam_role.athena_role.name
  policy_arn = aws_iam_policy.athena_policy.arn
}