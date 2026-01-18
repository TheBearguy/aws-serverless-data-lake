# Building a Serverless Data Lake on AWS — A Terraform-First, Failure-Driven Journey

---

## PART 1: FOUNDATION & CONTEXT

### 1. Introduction

This project didn't start with "let's build a data lake."

It started with: **"I want to understand Terraform deeply—state management, module architecture, resource ownership, and failure modes—in a real production-grade system."**

A serverless data lake became the perfect learning vehicle. Not because it's trendy or because "serverless" is a buzzword, but because it forces you to confront almost every hard Terraform problem early:

- State drift and recovery
- Resource ownership conflicts
- IAM complexity across multiple services
- Implicit dependencies between independently owned systems
- Module design decisions that make or break maintainability
- The consequences of treating infrastructure as throwaway code

This blog is a **Terraform-centric retrospective** where AWS services play supporting roles. The real story is about wrestling with Terraform itself: understanding how it tracks state, where it's unforgiving, where it stays silent, and how to architect infrastructure so that Terraform remains a powerful tool instead of becoming a liability.

If you're past the "hello world" stage of Terraform and want to see what happens when textbook concepts meet messy reality, this is for you.

**What you'll learn:**
- How to structure Terraform modules around ownership boundaries, not code reuse
- How to debug state drift without destroying everything
- How IAM failures expose architectural problems
- Why AWS documentation matters more than tutorials in production systems
- The specific pain points that only emerge when you actually run `terraform apply` on a real system

**What you won't find here:**
- Copy-paste starter templates
- "Just use this module from the registry" shortcuts
- Assumptions that everything works on the first try

This is the blog I wish I'd read before starting.

---

### 2. Mental Model Shift: From Pipeline to Contracts

Early in this project, I made a fundamental mistake. I was thinking about the system as a **pipeline**:

> "When a JSON file lands in S3, trigger Lambda to transform it, then Glue catalogs it, then Athena queries it."

This mental model seems intuitive. It's how most tutorials frame data ingestion systems. But in practice, it's wrong—or at least incomplete.

The problem with "pipeline thinking" is that it treats every component as a step in a sequence, where each step depends on the previous one working perfectly. When something breaks (and it will), you're left debugging a tangled web of implicit dependencies.

#### The Shift: Thinking in Contracts

Halfway through the project, I reframed everything. I stopped thinking about **pipelines** and started thinking about **contracts between independently owned systems**.

Here's what that means in practice:

**S3 owns data durability.**  
Its job is to store files reliably and durably. It doesn't care what's inside those files. It doesn't validate JSON structure. It doesn't know what Lambda does with them. Its contract is simple: "I will not lose your data."

**Lambda owns transformation logic.**  
Its job is to read a JSON file, flatten it deterministically, and write a Parquet file. It doesn't care where the JSON came from. It doesn't care what happens to the Parquet file downstream. Its contract: "Given this input, I produce this output."

**Glue owns metadata.**  
Its job is to catalog schema information so that query engines can understand what's in the data. It doesn't validate data correctness. It doesn't care how the data got there. Its contract: "I will tell you what columns exist and what types they are."

**Athena owns querying.**  
Its job is to read from the Glue catalog and execute SQL queries. It doesn't care how Parquet files were created. It doesn't fix schema problems. Its contract: "Give me a valid catalog and I'll run your query."

**Terraform owns the contracts.**  
Its job is to define who can talk to whom, under what conditions, and with what permissions. It doesn't care about application logic. It enforces boundaries.

#### Why This Reframe Mattered

Once I internalized this contract-based thinking, debugging became dramatically easier.

When something broke, I could immediately ask:
- **Which contract was violated?**
- **Which system failed to uphold its responsibility?**
- **Is this an application bug or an infrastructure boundary problem?**

For example, when Athena queries started failing, I didn't have to debug the entire "pipeline." I just asked:
1. Is the Parquet file valid? (Lambda's contract)
2. Is the schema cataloged correctly? (Glue's contract)
3. Does Athena have permission to read the catalog? (IAM contract)

This made failures **traceable** instead of mysterious.

This shift in thinking also changed how I structured Terraform. Instead of one big monolithic configuration that tries to model the entire "flow," I built independent modules that each own one contract.

More on that in the next section.

---

### 3. Project Overview

Before diving into Terraform architecture, let's establish what was actually built.

#### High-Level Architecture

Here's the data flow:

1. **JSON files uploaded to S3 raw bucket**  
   Users (or automated systems) drop JSON files into an S3 bucket under a specific prefix like `uploads/`.

2. **S3 event triggers Lambda**  
   S3 bucket notifications are configured to invoke a Lambda function whenever a new object is created.

3. **Lambda performs ETL**  
   The Lambda function reads the JSON, validates its structure, flattens nested fields, and writes a Parquet file to a curated S3 bucket.

4. **Glue crawler catalogs the data**  
   A scheduled Glue crawler scans the curated bucket, infers the schema from Parquet files, and creates/updates table definitions in the Glue Data Catalog.

5. **Athena queries the dataset**  
   Analysts run SQL queries via Amazon Athena, which reads from the Glue catalog and scans Parquet files in S3.

#### AWS Services Used

- **Amazon S3**: Two buckets—raw (immutable JSON) and curated (processed Parquet)
- **AWS Lambda**: Stateless ETL function triggered by S3 events
- **AWS Glue**: Managed metadata catalog and schema discovery via crawlers
- **Amazon Athena**: Serverless SQL query engine
- **AWS IAM**: Least-privilege roles for each service
- **CloudWatch**: Logging and monitoring for Lambda and Glue
- **Terraform**: The control plane that provisions and wires everything together

#### What "Serverless Data Lake" Actually Means

The term "serverless" is overloaded, so let me be specific about what it means here:

**No servers to manage:**  
No EC2 instances. No Kubernetes clusters. No Spark jobs running on EMR. Every compute resource is either Lambda (for ETL) or fully managed services (Glue, Athena).

**Pay-per-use:**  
Lambda charges per invocation and execution time. Athena charges per byte scanned. Glue crawlers charge per DPU-hour. You pay for what you use, not for idle capacity.

**Event-driven:**  
The system is reactive. Nothing runs unless data arrives. No polling. No scheduled jobs checking for work.

**Fully declarative:**  
Everything—buckets, functions, roles, permissions, catalog tables—is defined in Terraform. No manual configuration. No ClickOps.

This architecture is great for learning because it's **simple enough to understand** but **complex enough to expose real Terraform challenges**.

---

## PART 2: TERRAFORM ARCHITECTURE & DESIGN DECISIONS

### 4. Module Design Philosophy

One of the most important decisions I made early on—and then had to redo after failing—was how to structure Terraform modules.

#### Why Everything Became a Module

Every major component in this project lives in its own Terraform module:

```
modules/
├── s3/
├── iam/
├── lambda/
├── glue/
└── athena/
```

This wasn't about code reuse. I'm not planning to reuse these modules across multiple projects. I'm not building a Terraform module registry.

This was about **ownership clarity**.

#### The Core Principle: Modules Define Ownership Boundaries

A well-designed module answers one question unambiguously:

> **Which part of the system owns this resource?**

For example:

**The Lambda module owns:**
- The Lambda function itself
- The Lambda execution IAM role
- The CloudWatch log group for Lambda logs
- Environment variables and runtime configuration

**The Lambda module does NOT own:**
- S3 buckets (those belong to the S3 module)
- S3 event notifications (those are cross-system wiring, owned by root)
- Glue catalog tables (those belong to the Glue module)

This separation is not pedantic. It's critical for two reasons:

**1. Predictable state behavior**  
When you know exactly which module owns a resource, you know where to look when state drifts. You know which `terraform state` command to run. You know which module to destroy and recreate if something goes wrong.

**2. Prevents circular dependencies**  
If modules try to reference each other's resources directly, you get circular dependency errors that are hell to debug. By keeping modules independent and connecting them at the root level, you avoid this entirely.

#### The Rule I Learned: "Modules Create. Root Connects."

> **Modules create resources. Root configuration connects them.**

Here's what that looks like in practice.

**In the Lambda module (`modules/lambda/main.tf`):**

```hcl
resource "aws_lambda_function" "etl" {
  function_name = var.function_name
  handler       = var.handler
  runtime       = var.runtime
  role          = aws_iam_role.lambda_exec.arn
  filename      = var.lambda_zip_path
  
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = var.environment_variables
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.function_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.etl.function_name}"
  retention_in_days = 7
}

output "function_arn" {
  value = aws_lambda_function.etl.arn
}

output "function_name" {
  value = aws_lambda_function.etl.function_name
}
```

Notice: This module creates the Lambda function and its execution role. It does NOT create S3 buckets. It does NOT create S3 event notifications. It exposes outputs so that other parts of the system can reference it.

**In the root configuration (`main.tf`):**

```hcl
module "s3_buckets" {
  source = "./modules/s3"
  
  raw_bucket_name     = "my-data-lake-raw"
  curated_bucket_name = "my-data-lake-curated"
}

module "lambda_etl" {
  source = "./modules/lambda"
  
  function_name = "json-to-parquet-etl"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  lambda_zip_path = "${path.module}/lambda/lambda_function.zip"
  
  environment_variables = {
    CURATED_BUCKET = module.s3_buckets.curated_bucket_name
  }
}

# Root owns the wiring between systems
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_etl.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_buckets.raw_bucket_arn
}

resource "aws_s3_bucket_notification" "trigger_lambda" {
  bucket = module.s3_buckets.raw_bucket_id

  lambda_function {
    lambda_function_arn = module.lambda_etl.function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}
```

Notice: The root configuration instantiates both modules. It passes outputs from one module as inputs to another (`module.s3_buckets.curated_bucket_name`). And crucially, it creates the **cross-system wiring** (S3 → Lambda event notification) without either module knowing about the other.

This pattern kept my Terraform state clean and made `terraform plan` output readable.

---

### 5. Root Orchestration Strategy

The root `main.tf` file is the orchestration layer. Its job is narrow and intentional.

#### What Root Does

1. **Instantiates modules with explicit inputs**  
   Every module receives its configuration as variables. No hidden defaults. No assumptions.

2. **Passes outputs from one module as inputs to another**  
   For example, the Lambda module needs to know the curated bucket name. Root passes `module.s3_buckets.curated_bucket_name` to the Lambda module's `environment_variables`.

3. **Defines cross-system dependencies**  
   S3 event notifications. IAM policy attachments that grant one service access to another. These live in root because they represent contracts between independently owned systems.

#### What Root Does NOT Do

1. **Create individual resources directly**  
   Almost no `resource` blocks live in root (except for wiring like S3 notifications). Everything else is delegated to modules.

2. **Contain business logic**  
   Root doesn't know about JSON schemas, Parquet compression, or Glue crawler schedules. That's module-level detail.

3. **Try to be "smart" about dependencies**  
   Terraform's implicit dependency graph handles most ordering. When explicit ordering is needed, I use `depends_on`. No hacks.

#### Why This Matters

This separation makes the system **debuggable**.

When something breaks, I can immediately identify:
- Which module owns the broken resource
- Which outputs are being passed where
- Which wiring is suspect

For example, when Lambda couldn't write to the curated bucket (IAM permission error), I knew the problem was either:
1. The Lambda module's IAM role definition
2. The S3 module's bucket policy
3. The root's wiring between them

I didn't have to grep through the entire `main.tf` file wondering where permissions were granted.

---

### 6. State Management Strategy

Terraform state is one of those things that seems simple until it isn't.

Early on, I treated state as "Terraform's internal thing that I don't need to worry about." That was naive. State management became one of the most educational parts of this project.

#### State Is a Contract, Not a Cache

Here's the mental model that finally clicked for me:

> **Terraform state is not a mirror of AWS reality.**  
> **It's a contract defining what *should* exist.**

This distinction matters because Terraform doesn't constantly poll AWS to check if resources still exist. It trusts its state file.

#### Learning State Drift the Hard Way

One day, I got frustrated debugging a Glue crawler issue. The crawler kept failing with cryptic permission errors. In a moment of impatience, I deleted the crawler manually in the AWS console, thinking I'd just recreate it cleanly via Terraform.

I ran `terraform plan`.

Output: **No changes. Your infrastructure matches the configuration.**

Wait, what?

I ran `terraform apply`.

Still nothing. Terraform thought the crawler still existed because the state file said it existed.

This was my "oh shit" moment with Terraform state.

#### What I Learned

**Lesson 1: Never delete resources outside of Terraform**  
If Terraform created it, only Terraform should modify or destroy it. Breaking this rule creates state drift.

**Lesson 2: `terraform refresh` is not a magic fix**  
Running `terraform refresh` updates the state file to match AWS reality, but only if Terraform can successfully query the resource. If a resource is gone, Terraform doesn't detect that during refresh—it just fails silently.

**Lesson 3: `terraform state rm` is a recovery tool**  
When state drift happens (because you screwed up and deleted something manually), you have two options:
1. Manually import the resource back into state if it still exists in AWS
2. Remove it from state with `terraform state rm` and let Terraform recreate it

I used option 2:

```bash
terraform state rm module.glue.aws_glue_crawler.users_crawler
terraform apply
```

This told Terraform: "Forget about this resource in state. Now create it fresh."

**Lesson 4: State drift is a design smell**  
If you're regularly experiencing state drift, something is wrong with your workflow:
- Someone is doing ClickOps (manual changes in the AWS console)
- Your Terraform config doesn't fully own the resources it thinks it does
- You're mixing Terraform with other automation tools without proper coordination

In my case, the culprit was me. I was the one breaking the contract. The fix wasn't technical—it was discipline.

#### Current State Setup

Right now, I'm using a single local state file:

```
terraform.tfstate
```

This works fine for a solo learning project. But it has limitations:
- No collaboration (state is on my laptop)
- No locking (no protection against concurrent applies)
- No history (state file just gets overwritten)

#### State Splitting Plan for Complex Projects

For a production system, I'd split this into multiple state files:

1. **Foundation state**: S3 buckets, IAM roles, base infrastructure
2. **Ingestion state**: Lambda functions, S3 event wiring
3. **Catalog state**: Glue databases, crawlers, table definitions
4. **Query state**: Athena workgroups, result buckets

Each state would live in its own S3 backend with DynamoDB locking:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "data-lake/ingestion/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

This would enable:
- Independent lifecycle management (change Lambda without touching Glue)
- Team collaboration (multiple people working on different layers)
- Blast radius isolation (breaking ingestion doesn't touch the catalog)

But for learning? Single local state is fine. Overengineering state management before understanding state behavior is bad.

---

### 7. IAM as Architectural Boundaries

IAM was the most frustrating—and most educational—part of this project.

I came in thinking: "IAM is just permissions. Grant access, move on."

I left understanding: **IAM is how you enforce architectural boundaries at runtime.**

#### Role-Per-Service Model

Every service in this system gets its own IAM role:

1. **LambdaExecutionRole**
2. **GlueCrawlerRole**
3. **AthenaQueryRole**

This wasn't about security theater. It was about **making system boundaries explicit**.

#### LambdaExecutionRole: Narrow and Intentional

Lambda's role grants exactly what Lambda needs to do its job, and nothing more:

```hcl
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-json-to-parquet-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "LambdaS3Access"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.raw.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.curated.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
```

**What this grants:**
- Read access to the raw bucket (to fetch JSON files)
- Write access to the curated bucket (to write Parquet files)
- CloudWatch Logs access (via the managed `AWSLambdaBasicExecutionRole` policy)

**What this does NOT grant:**
- Write access to the raw bucket (enforces immutability)
- Access to Glue catalog (Lambda doesn't need it)
- Access to Athena (Lambda doesn't query data)

#### Why Tight IAM Scopes Make Debugging Easier

When Lambda fails with an S3 permission error, I know immediately:
- It's not a Glue problem
- It's not an Athena problem
- It's an S3 access issue

The IAM role tells me exactly what Lambda is allowed to do. If Lambda tries to do something outside that scope, AWS rejects it immediately with a clear error message.

This is **architectural clarity enforced at runtime**.

#### GlueCrawlerRole: More Complex Than Expected

The Glue crawler role was where I learned the most. More on the specific failures in Part 4, but here's the final role definition:

```hcl
resource "aws_iam_role" "glue_crawler" {
  name = "glue-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# Managed policy for basic Glue operations
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy for S3 data access
resource "aws_iam_policy" "glue_s3_access" {
  name = "GlueS3Access"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.curated.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          # Databases
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:CreateDatabase",
          "glue:UpdateDatabase",

          # Tables
          "glue:GetTable",
          "glue:GetTables",
          "glue:CreateTable",
          "glue:UpdateTable",

          # Partitions (ALL required)
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition",
          "glue:CreatePartition",
          "glue:UpdatePartition",
          "glue:BatchCreatePartition",

          # Crawler control
          "glue:GetCrawler",
          "glue:CreateCrawler",
          "glue:UpdateCrawler",
          "glue:StartCrawler"
        ]
        Resource = aws_s3_bucket.curated.arn
      }
    ]
  })
}

# Custom policy for CloudWatch logging
resource "aws_iam_role_policy" "glue_logging" {
  name = "GlueLogging"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:/aws-glue/*"
    }]
  })
}
```

**Key takeaway:** The managed `AWSGlueServiceRole` policy is NOT sufficient. It grants Glue catalog access but doesn't include S3 data access or CloudWatch logging permissions. You have to add those explicitly.

I only learned this by failing repeatedly. More on that in Part 4.

#### IAM Taught Me About System Boundaries

Every IAM failure in this project pointed to a misunderstanding about system boundaries:

- When Lambda couldn't write to S3 → I didn't understand S3 bucket ownership
- When Glue couldn't log to CloudWatch → I didn't understand Glue's runtime requirements
- When Athena couldn't read the catalog → I didn't understand Glue catalog permissions

IAM errors aren't noise. They're **architectural feedback**. They force you to ask: "Should this component really have access to that resource?"

Often, the answer is no. And that's a good thing. Tight IAM boundaries make systems safer and easier to reason about.

---

## PART 3: AWS SERVICES & IMPLEMENTATION DETAILS

### 8. S3 Storage Design

S3 is the foundation of this entire system. Everything else—Lambda, Glue, Athena—reads from or writes to S3. Getting the storage design right was critical.

#### Raw vs. Curated Bucket Separation

One of the first architectural decisions: **raw data and curated data live in separate buckets.**

This wasn't about performance or cost. It was about **immutability guarantees**.

**Raw bucket (`my-data-lake-raw`):**
- Contains original JSON files exactly as uploaded
- Write-once, read-many
- No lifecycle policies that delete data automatically
- Versioning enabled (though rarely used in practice)
- IAM: Only uploaders and Lambda can write; Lambda can read; Glue cannot touch it

**Curated bucket (`my-data-lake-curated`):**
- Contains processed Parquet files written by Lambda
- Lambda writes, Glue reads, Athena queries
- Lifecycle policies can archive old data after 90 days (optional)
- IAM: Only Lambda can write; Glue and Athena can read

**Why this separation matters:**

1. **Replayability**: If Lambda ETL logic changes, I can reprocess raw data without losing the original inputs
2. **Debugging**: If curated data looks wrong, I can always check the raw source
3. **Blast radius**: If someone accidentally deletes curated data, raw data is untouched

This design is enforced via IAM policies, not just bucket-level permissions.

#### Prefix Strategy: Not Just "Folders"

S3 prefixes aren't just organizational conveniences. They're **data contracts** that affect downstream behavior.

My prefix structure:

```
raw/
  uploads/YYYY/MM/DD/filename.json

curated/
  datasets/
    users/v1/user_12345.parquet
    events/v1/event_67890.parquet
```

**Why this structure?**

**1. Partition pruning for Athena**  
The `YYYY/MM/DD/` pattern in the raw bucket isn't just for humans. If I ever query raw JSON directly (via Glue crawler + Athena), Athena can skip scanning entire months of data based on the prefix.

**2. Schema versioning**  
The `/v1/` subdirectory under each dataset allows me to introduce breaking schema changes in `/v2/` without breaking existing Athena queries. Old queries continue reading from `/v1/`. New queries use `/v2/`.

This is critical for systems that evolve over time. Without version prefixes, schema changes become all-or-nothing migrations.

**3. Glue crawler scoping**  
Glue crawlers need to be pointed at specific prefixes. If you point a crawler at `s3://bucket/curated/datasets/`, it will try to infer a single schema across all subdirectories. That's almost never what you want.

Instead, each crawler targets one dataset version:

```hcl
resource "aws_glue_crawler" "users_v1" {
  name          = "users-v1-crawler"
  database_name = aws_glue_catalog_database.data_lake.name
  role          = aws_iam_role.glue_crawler.arn

  s3_target {
    path = "s3://${aws_s3_bucket.curated.id}/datasets/users/v1/"
  }
}
```

This scoping prevents schema conflicts and keeps crawlers fast.

#### Lifecycle Policies and Versioning

For the raw bucket, I enabled versioning but no lifecycle policies:

```hcl
resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

---

### 9. Lambda ETL Layer

Lambda is the transformation engine. Its job is narrow and intentional.

#### What Lambda Should Do (and Shouldn't Do)

**Lambda's responsibilities:**
1. Read a JSON file from the raw S3 bucket
2. Validate its structure (basic checks: required fields exist, types are correct)
3. Flatten nested JSON fields into a flat schema
4. Write a Parquet file to the curated S3 bucket
5. Log success or failure to CloudWatch
6. Exit

**Lambda does NOT:**
- Infer schemas dynamically (that's Glue's job)
- Make decisions about downstream processing (that's Athena's job)
- Retry failed writes indefinitely (S3 handles durability)
- Manage metadata (that's Glue's job)
- Join data from multiple sources (that's analytics logic, not ETL)

This discipline kept Lambda **deterministic**. Given the same input JSON, Lambda always produces the same Parquet output.

#### Keeping Lambda Deterministic

Determinism is critical for reprocessing. If Lambda behavior changes randomly (timestamp-based logic, random sampling, etc.), you can't safely replay historical data.

My Lambda function follows strict rules:
- No system timestamps (use timestamps from the JSON payload)
- No random number generation
- No external API calls (except S3 read/write)
- No stateful operations (Lambda is stateless by design)

This means I can always reprocess raw data and get identical results.

#### Lambda Function Structure

Here's the skeleton of the Lambda handler:

```python
import json
import boto3
import pyarrow as pa
import pyarrow.parquet as pq
from io import BytesIO

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    # Extract S3 event details
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    # Read JSON from S3
    response = s3_client.get_object(Bucket=bucket, Key=key)
    json_data = json.loads(response['Body'].read())
    
    # Flatten nested fields
    flattened = flatten_json(json_data)
    
    # Convert to Parquet
    parquet_buffer = write_parquet(flattened)
    
    # Write to curated bucket
    curated_bucket = os.environ['CURATED_BUCKET']
    output_key = key.replace('uploads/', 'datasets/users/v1/').replace('.json', '.parquet')
    
    s3_client.put_object(
        Bucket=curated_bucket,
        Key=output_key,
        Body=parquet_buffer.getvalue()
    )
    
    return {'statusCode': 200, 'body': 'Success'}

def flatten_json(data):
    # Flattening logic here
    pass

def write_parquet(data):
    # Parquet writing logic here
    pass
```

Notice:
- Environment variable `CURATED_BUCKET` is passed via Terraform
- Output key is derived deterministically from input key
- No external dependencies beyond S3 and Parquet libraries

#### Packaging Discipline: Terraform

<invoke name="artifacts">
<parameter name="command">update</parameter>
<parameter name="id">terraform_data_lake_blog</parameter>
<parameter name="old_str">#### Packaging Discipline: Terraform</parameter>
<parameter name="new_str">#### Packaging Discipline: Terraform Doesn't Build Code

One critical lesson I learned: **Terraform deploys artifacts. It does not build them.**

Early on, I kept hitting Lambda deployment issues:
- Missing Python dependencies
- Incorrect ZIP structure
- Handler path mismatches

Every time, Terraform applied successfully. The Lambda function was created. But it failed at runtime when S3 tried to invoke it.

This taught me: **Terraform validates infrastructure syntax, not application correctness.**

---

### 10. Writing Correct Parquet Files

Parquet is not just "another file format." It's a **columnar storage format with strict schema contracts**.

#### Why Parquet Is a Contract, Not Just a Format

Bad Parquet files are worse than raw JSON. Here's why:

**JSON fails obviously:**
- Invalid syntax → parse error immediately
- Missing field → `null` or KeyError
- Wrong type → coercion or exception

**Parquet fails silently:**
- Wrong schema → Athena reads garbage data
- Corrupted row groups → partial data loss
- Bad compression → query performance degrades
- Type mismatches → silent data corruption

This makes Parquet correctness **critical**.


---

### 11. Glue Crawlers: Schema Discovery

Glue crawlers are powerful but dangerous. They automate schema inference, which sounds great—until it silently produces the wrong schema.

#### What Glue Crawlers Actually Do

A Glue crawler:
1. Samples data files from an S3 prefix (10% by default)
2. Infers a schema based on file structure (column names, types)
3. Creates or updates a table definition in the Glue Data Catalog

This works great for exploration. It's risky for production.


#### When Crawlers Succeed But Produce No Tables

This was one of the most frustrating bugs.

Glue crawler runs. Status: **Succeeded**. Tables created: **0**.

No error message. No logs in the console (initially).

**Possible causes:**
1. S3 prefix is wrong (crawler scanned empty directory)
2. Files exist but are malformed (crawler couldn't parse them)
3. IAM permissions are insufficient (crawler couldn't read files)

I wasted hours debugging this before I learned: **Glue crawler logs are in CloudWatch, not the Glue console.**

**The fix: Explicit log group**

```hcl
resource "aws_cloudwatch_log_group" "glue_crawler_logs" {
  name              = "/aws-glue/crawlers/${aws_glue_crawler.users_v1.name}"
  retention_in_days = 7
}
```

Now when a crawler fails silently, I check CloudWatch Logs and see:

```
ERROR: Unable to infer schema for s3://bucket/datasets/users/v1/
REASON: No valid Parquet files found
```

That tells me the problem immediately.

---

### 12. Athena Query Layer

Athena is the final piece. It's a serverless SQL query engine that reads from the Glue catalog.

#### Athena Is a Consumer, Not a Healer

Athena worked almost immediately—**after everything upstream was correct**.

That itself was instructive:

> **Athena exposes problems. It doesn't fix them.**

If the Parquet schema is wrong, Athena queries return garbage.  
If the Glue catalog is incomplete, Athena sees missing columns.  
If S3 permissions are broken, Athena fails with `Access Denied`.

Athena is a **read boundary**. It assumes the data pipeline is correct.

#### Cost Controls: Workgroups and Scan Limits

Athena charges per byte scanned. Without guardrails, this can get expensive.

**Terraform-enforced controls:**

```hcl
resource "aws_athena_workgroup" "data_lake" {
  name = "data-lake-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/results/"
    }

    bytes_scanned_cutoff_per_query = 1073741824  # 1 GB limit
  }
}
```

**What this does:**
- **Enforce workgroup config**: Users can't override these settings
- **Result location**: Query results are written to a dedicated bucket
- **Scan limit**: Queries that would scan more than 1 GB are rejected

This prevents accidental full-table scans from running up the AWS bill.

**Example failure:**

```sql
SELECT * FROM users;  -- Scans entire table
```

If the table is > 1 GB, Athena rejects this query with:

```
Query exhausted resources at this scale factor.
```

The fix: Add a `LIMIT` or `WHERE` clause to reduce scan size.

This keeps query results organized and costs predictable.

---

## PART 4: FAILURES, DEBUGGING, AND LESSONS LEARNED

### 13. Failure Category 1: State Management Issues

#### The Problem

I got frustrated debugging a Glue crawler issue. The crawler kept failing with cryptic permission errors. In a moment of impatience, I deleted the crawler manually in the AWS console, thinking I'd just recreate it cleanly via Terraform.

I ran `terraform plan`.

Output:

```
No changes. Your infrastructure matches the configuration.
```

Wait, what? I just deleted the crawler. Why isn't Terraform recreating it?

I ran `terraform apply`.

```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

Still nothing.

#### Root Cause

Terraform state is not a mirror of AWS reality. It's a **contract defining what should exist**.

When I deleted the Glue crawler in the AWS console, I broke that contract. But Terraform didn't know. Its state file still said the crawler existed.

Terraform only checks AWS reality when you explicitly tell it to (via `terraform refresh`). Otherwise, it trusts its state file.

#### How I Debugged It

First, I tried `terraform refresh`:

```bash
terraform refresh
```

This updated the state file... but Glue resources don't always refresh cleanly. The state still showed the crawler as existing.

Then I checked the actual state file:

```bash
terraform state list | grep glue
```

Output:

```
module.glue.aws_glue_crawler.users_v1
```

So Terraform still thought it owned the crawler.

#### The Solution

I removed the resource from state and let Terraform recreate it:

```bash
terraform state rm module.glue.aws_glue_crawler.users_v1
terraform apply
```

Output:

```
Plan: 1 to add, 0 to change, 0 to destroy.

  + module.glue.aws_glue_crawler.users_v1
      name: "users-v1-crawler"
      role: "arn:aws:iam::..."
```

Now Terraform recreated the crawler from scratch.

#### Lesson Learned

**Never delete resources outside of Terraform.**

If Terraform created it, only Terraform should modify or destroy it. Breaking this rule creates state drift that's painful to debug.

**`terraform state rm` is a recovery tool, not a shortcut.**

Use it deliberately when state drift happens, but treat it as a last resort. The correct fix is to not create drift in the first place.

**State drift is a design smell.**

If you're regularly experiencing state drift, something is wrong:
- Someone is doing ClickOps (manual AWS console changes)
- Your Terraform config doesn't fully own the resources it thinks it does
- You're mixing Terraform with other automation without coordination

In my case, the culprit was me. I needed discipline, not better tooling.

---

### 14. Failure Category 2: IAM Permission Hell

This was the most educational (and frustrating) set of failures.

#### Problem 1: Glue Crawler Can't Log

**Error message:**

```
AccessDeniedException: User: arn:aws:sts::xxx:assumed-role/GlueCrawlerRole 
is not authorized to perform: logs:PutLogEvents on resource: arn:aws:logs:...
```

The Glue crawler ran but couldn't write logs to CloudWatch.

#### Root Cause

The managed `AWSGlueServiceRole` policy doesn't include CloudWatch Logs permissions.

Here's what the managed policy grants:
- `glue:*` on Glue catalog resources
- `s3:GetObject` on buckets tagged as Glue-accessible (but not arbitrary buckets)

Here's what it does NOT grant:
- CloudWatch Logs access
- S3 access to specific buckets

#### How I Debugged It

First, I checked what permissions the role actually had:

```bash
aws iam list-attached-role-policies --role-name GlueCrawlerRole
```

Output:

```json
{
  "AttachedPolicies": [
    {
      "PolicyName": "AWSGlueServiceRole",
      "PolicyArn": "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
    }
  ]
}
```

Then I looked up the managed policy in AWS documentation:

https://docs.aws.amazon.com/glue/latest/dg/create-service-policy.html

The docs clearly state:

> The AWSGlueServiceRole managed policy grants permissions to Glue catalog operations. You must attach additional policies for S3 access and CloudWatch Logs.

**YouTube tutorials lied by omission.**

Every tutorial I watched said: "Just attach `AWSGlueServiceRole` and you're done!"

That's incomplete. The managed policy is a starting point, not the full solution.

#### The Solution

I added an explicit policy for CloudWatch Logs:

```hcl
resource "aws_iam_role_policy" "glue_logging" {
  name = "GlueLogging"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:/aws-glue/*"
    }]
  })
}
```

Now the crawler could log to CloudWatch.

#### Problem 2: Glue Crawler Can't Read S3 Data

**Error message:**

```
InternalServiceException: Insufficient permissions to access the data location.
```

The crawler could see the S3 bucket but couldn't read files.

#### Root Cause

The managed `AWSGlueServiceRole` policy grants S3 access only for buckets tagged with `aws-glue-default-database`.

My curated bucket wasn't tagged. And even if it were, I wanted explicit control over permissions.

#### The Solution

I added an explicit S3 access policy:

```hcl
resource "aws_iam_role_policy" "glue_s3_access" {
  name = "GlueS3Access"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.curated.arn}/*"
      },
      {
        Effect = "Allow"
        Action = "s3:ListBucket"
        Resource = aws_s3_bucket.curated.arn
      }
    ]
  })
}
```

Notice:
- `s3:GetObject` and `s3:PutObject` on objects (`/*`)
- `s3:ListBucket` on the bucket itself (no `/*`)

This is a common IAM gotcha. `ListBucket` is a bucket-level permission, not an object-level permission.

#### Problem 3: Glue Crawler Can't Update Catalog

**Error message:**

```
AccessDeniedException: User is not authorized to perform: glue:BatchCreatePartition
```

The crawler could read files but couldn't update the Glue catalog.

#### Root Cause

The managed `AWSGlueServiceRole` grants read permissions on the catalog but not write permissions for partition operations.

#### The Solution

I added explicit Glue catalog write permissions:

```hcl
resource "aws_iam_role_policy" "glue_catalog_write" {
  name = "GlueCatalogWrite"
  role = aws_iam_role.glue_crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "glue:BatchCreatePartition",
        "glue:BatchGetPartition",
        "glue:UpdateTable",
        "glue:UpdateDatabase"
      ]
      Resource = "*"
    }]
  })
}
```

Now the crawler had full catalog access.

#### How I Actually Solved This

Using ChatGPT and by reading **AWS Glue IAM documentation**:

https://docs.aws.amazon.com/glue/latest/dg/security-iam.html

The docs list every action Glue might need. They explain when each action is required. They provide example policies.

This was slow. It was boring. But it was **correct**.

#### Lesson Learned

**IAM errors are architectural feedback, not noise.**

Every IAM failure forced me to ask:
- What is this service actually trying to do?
- Why does it need this permission?
- Should it really have access to this resource?

Often, the answer clarified my understanding of how the system actually works.

**AWS documentation is boring but essential.**

When Terraform fails at apply-time, AWS docs explain *why*, not just *what*.

Error messages are breadcrumbs pointing back to service contracts defined in the docs.

**Managed policies are incomplete by design.**

AWS provides managed policies like `AWSGlueServiceRole` as starting points, not complete solutions. You must add service-specific policies for S3, CloudWatch, etc.

Tutorials that claim "just use the managed policy" are lying by omission.

---

### 15. Failure Category 3: Lambda Runtime Issues

#### Problem 1: Handler Not Found

**Error message:**

```
Runtime.HandlerNotFound: lambda_function.lambda_handler
```

Lambda was created successfully. It deployed without errors. But when S3 tried to invoke it, it failed immediately.

#### Root Cause

The handler path in Terraform didn't match the actual file structure.

My Terraform config:

```hcl
resource "aws_lambda_function" "etl" {
  function_name = "json-to-parquet-etl"
  handler       = "handler.lambda_handler"  # WRONG
  runtime       = "python3.9"
  filename      = "${path.module}/lambda/lambda_function.zip"
  # ...
}
```

My Python file was named `lambda_function.py` with a function called `lambda_handler()`.

The handler path should've been:

```hcl
handler = "lambda_function.lambda_handler"
```

#### How I Debugged It

First, I checked the Lambda function logs in CloudWatch:

```
Runtime.HandlerNotFound: handler.lambda_handler
```

That told me Lambda was looking for a file called `handler.py`, but my file was `lambda_function.py`.

Then I inspected the ZIP file:

The file was definitely named `lambda_function.py`.

#### The Solution

Fixed the handler path in Terraform:

```hcl
handler = "lambda_function.lambda_handler"
```

Ran `terraform apply`, and Lambda worked.

#### Lesson Learned

**Terraform deploys artifacts. It doesn't validate them.**

Terraform checks that the ZIP file exists. It uploads it to S3. It creates the Lambda function.

But it does NOT validate:
- Whether the handler path is correct
- Whether dependencies are included
- Whether the code is syntactically valid

Those failures only surface at **runtime**, not at `terraform apply` time.

**Test Lambda locally before deploying.**

I should've tested the handler path locally with:

```bash
python -c "from lambda_function import lambda_handler; print(lambda_handler)"
```

This would've caught the error before Terraform ever ran.

---

#### Lesson Learned

**Parquet schema must match Glue catalog expectations.**

If Lambda writes strings but Glue thinks they're timestamps, queries fail.

**Always specify schema explicitly.**

Don't rely on PyArrow's type inference. Explicitly define the schema:
```python
schema = pa.schema([
    ('timestamp', pa.timestamp('ms')),
    ('user_id', pa.string()),
    ('amount', pa.float64()),
])
```

**Use `parquet-tools` to debug schema issues.**

Athena error messages are cryptic. Parquet-tools shows the actual file schema, making mismatches obvious.

**Read AWS documentation on Parquet data types.**

https://docs.aws.amazon.com/athena/latest/ug/data-types.html

This page maps Athena types to Parquet types. It's boring. It's essential.

---

## PART 5: META-LESSONS & REFLECTIONS

### 18. Documentation vs. YouTube: A Hard Truth

One of the most important meta-lessons from this project:

> **Videos optimize for confidence. Documentation optimizes for correctness.**

#### Why YouTube Tutorials Failed Me

YouTube videos gave me the initial mental model:
- "Here's how S3 events work"
- "This is what a Lambda handler looks like"
- "Glue crawlers are easy—just attach this managed policy!"

They were great for understanding the **shape** of the solution.

But every hard bug—IAM permissions, handler naming, Parquet schema mismatches—was only solvable by reading AWS documentation carefully.

#### Why Documentation and AI Won

**AWS documentation is:**

1. **Exhaustive**: Covers edge cases that videos skip
2. **Precise**: Defines exact action names, resource ARNs, required parameters
3. **Versioned**: Updated when APIs change
4. **Authoritative**: Written by the team that built the service

**YouTube videos are:**

1. **Optimistic**: Show the happy path, ignore failure modes
2. **Outdated**: A 2-year-old video might use deprecated APIs
3. **Incomplete**: Skip "boring" details like IAM permissions to keep runtime under 10 minutes
4. **Generalized**: Try to appeal to beginners, sacrificing depth

#### Lesson Learned

**When Terraform fails, documentation explains why.**

Error messages are breadcrumbs pointing back to service contracts defined in AWS docs.

**Don't trust tutorials for production systems.**

They're great for exploration. They're insufficient for correctness.

**Read the boring stuff.**

The least exciting part of AWS documentation—IAM actions, resource ARNs, required parameters—is the most critical.

Terraform rewards this discipline because it's unforgiving of half-understood concepts.

---

### 19. What Terraform Actually Taught Me

Looking back, this project taught me more about Terraform than any course or tutorial ever could.

#### 1. Modules Are About Ownership, Not Reuse

Before this project, I thought modules were for code deduplication.

Now I understand: **Modules define ownership boundaries.**

A well-designed module answers: *What does this component own, and what does it not touch?*

The Lambda module owns the function and its execution role. It does NOT own S3 buckets or event notifications.

This separation makes state predictable and debugging tractable.

#### 2. State Is a Contract, Not a Cache

Terraform state is not a mirror of AWS reality. It's a **contract about what should exist**.

When state drifts (because you deleted something manually), it's not a Terraform bug—it's a signal that you violated the contract.

The fix isn't technical. It's disciplinary: **If Terraform created it, only Terraform modifies it.**

#### 3. IAM Errors Are Architectural Feedback

Every IAM failure forced me to ask:
- What is this service actually trying to do?
- Why does it need this permission?
- Should it really have access to this resource?

IAM isn't just security boilerplate. It's **architectural documentation enforced at runtime**.

Tight IAM boundaries make systems safer and easier to debug.

#### 4. Terraform Exposes Bad Design Early

Many bugs in this project weren't AWS issues. They were architectural mismatches that Terraform surfaced through:
- Cryptic error messages (missing IAM permissions)
- Confusing plan diffs (hidden dependencies)
- Silent no-ops (state drift)

Terraform doesn't let you hide complexity. It forces you to confront it.



#### 5. You Can't Hide Complexity

Some infrastructure problems seem like they should have clean, elegant solutions.

In reality, they're messy:
- IAM policies with 20+ actions
- Glue crawlers with subtle prefix scoping rules
- Parquet schemas that must exactly match Glue catalog types

Terraform forces you to make all of this explicit. You can't abstract it away.

That explicitness is uncomfortable. But it's also honest.

---

### 20. Results & System Qualities

At the end of this project, the system has these properties:

✅ **Raw data is immutable and replayable**  
Original JSON files are never modified or deleted. If ETL logic changes, I can reprocess historical data without losing source truth.

✅ **Curated data is deterministic and queryable**  
Given the same input, Lambda always produces the same Parquet output. No randomness. No timestamps. No side effects.

✅ **Schema evolution is explicit, not accidental**  
Version prefixes (`/v1/`, `/v2/`) allow schema changes without breaking existing queries. Glue crawlers scope to specific versions.

✅ **Terraform state is stable and predictable**  
I can destroy and recreate the entire system without state drift. Modules own resources cleanly. Dependencies are explicit.

✅ **Failures are debuggable thanks to CloudWatch Logs**  
IAM boundaries make errors traceable. CloudWatch Logs capture detailed failures. Parquet-tools validate file schemas. I know where to look when something breaks.

The system works—but more importantly, **it makes sense**.
---

### 21. Conclusion

Terraform isn't just a provisioning tool. Used properly, it's a **design discipline**—one that forces clarity, punishes shortcuts, and rewards deliberate thinking.

*If you're early in your Terraform journey: this blog will be helpful because I build fewer smaller things, but understand them deeply.*</parameter>