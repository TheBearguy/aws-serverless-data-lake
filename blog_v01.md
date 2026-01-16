# Designing a Serverless Data Lake on AWS with Terraform  
*A state-safe, failure-aware approach to infrastructure as code*

---

## Introduction

Most tutorials make building a serverless data lake look deceptively simple:  
*S3 → Lambda → Glue → Athena*.  

In practice, that naïve pipeline breaks down quickly. Schema drift, partial failures, Glue crawler surprises, IAM edge cases, and Terraform state conflicts show up long before the system reaches production scale.

This post documents a **real Terraform-first project** that builds a serverless data lake on AWS while deliberately addressing those failure modes up front. The goal was not to “get something working,” but to design infrastructure that remains understandable, debuggable, and evolvable over time.

Terraform was chosen not just as a provisioning tool, but as a **control plane**: a way to encode ownership, boundaries, and invariants into the infrastructure itself.

By the end of this article, you’ll understand how to:

- Design a serverless data lake around **data contracts**, not event chains
- Structure Terraform modules to avoid state conflicts
- Use IAM and S3 layout to *enforce* correct data flow
- Integrate Lambda, Glue, and Athena without creating operational debt

---

## Project Overview

### What Was Built

The project implements a serverless ingestion and analytics pipeline with the following flow:

1. Raw JSON files are uploaded to S3  
2. An S3 event triggers a Lambda function  
3. Lambda flattens JSON and writes Parquet to a curated S3 location  
4. A Glue crawler catalogs the Parquet data  
5. Athena queries the dataset using the Glue Data Catalog  

The pipeline is fully provisioned using Terraform.

### Cloud Provider and Services

- **AWS S3** – raw and curated storage
- **AWS Lambda** – deterministic ETL
- **AWS Glue** – schema cataloging
- **AWS Athena** – query engine
- **AWS IAM** – strict access control
- **Terraform** – infrastructure orchestration and state management

### High-Level Architecture



Raw JSON (S3)
↓
Lambda (flatten + Parquet)
↓
Curated Parquet (S3)
↓
Glue Data Catalog
↓
Athena Queries


The critical distinction is that this is not treated as a single “pipeline,” but as a **series of contracts** between independently managed components.

### Design Goals

- Raw data is immutable and replayable
- Transformations are deterministic
- Schema changes are explicit and versioned
- Terraform state remains stable over time
- Each service has a clearly scoped responsibility

---

## Reframing the Problem: Pipelines vs Data Contracts

A common mistake is to think in terms of event flow:

> “When this happens, trigger that.”

Instead, the system was designed around **data contracts**:

- Raw data has a defined shape and lifecycle
- Curated data has a strict schema and location
- Metadata reflects the curated layout exactly
- Queries never depend on transformation logic

This reframing matters because failures don’t stop at service boundaries. A broken schema, a misconfigured crawler, or an overly broad IAM role can silently corrupt the entire lake.

Terraform is used here to **encode those contracts** in infrastructure, not just create resources.

---

## Data Modeling Decisions (Before Terraform)

Infrastructure decisions are downstream of data decisions.

Before writing any Terraform, the following questions were answered:

- Is the JSON deeply nested or shallow?
- Do arrays represent entities or attributes?
- Is schema evolution additive or breaking?

Flattening logic was treated as **schema policy**, not an implementation detail. Arrays that represented entities were normalized into separate datasets; unstable fields were versioned instead of inferred dynamically.

The key rule enforced throughout the system:

> **If the schema changes, the storage path changes.**

---

## S3 Design: Buckets, Prefixes, and Immutability

### Separate Buckets by Responsibility

Two primary buckets were used:

- **Raw bucket**  
  - Immutable, append-only  
  - Stores original JSON payloads  
- **Curated bucket**  
  - Stores Parquet output  
  - Organized for query efficiency  

This separation is not cosmetic. IAM policies rely on it to prevent accidental data corruption.

### Prefix Strategy

A simplified curated layout:

curated/
dataset/
schema=0.0.3/
year=2026/
month=01/
day=13/
*.parquet


This layout enables:

- Athena partition pruning
- Schema version isolation
- Safe backfills and reprocessing

S3 prefixes are treated as **data contracts**, not folders.

---

## Eventing and ETL with Lambda

### S3 → Lambda Trigger

S3 notifications are scoped tightly using suffix and prefix filters. Lambda is triggered only for raw JSON uploads and never for its own Parquet output.

This prevents recursive invocations and accidental loops.

### Lambda’s Narrow Responsibility

Lambda performs exactly four actions:

1. Validate input JSON
2. Apply a known schema mapping
3. Write Parquet to the curated bucket
4. Emit logs and metrics

What Lambda explicitly does **not** do:

- Infer schemas dynamically
- Handle cross-file joins
- Mutate raw data
- Discover output locations at runtime

This keeps Lambda deterministic and replaceable.

---

## Writing Correct Parquet

Parquet is treated as an API boundary.

Decisions were made explicitly around:

- Column types (never inferred dynamically)
- Compression (Snappy)
- Nullability rules
- Partition compatibility with Athena

Bad Parquet is worse than raw JSON. Terraform can’t fix schema mistakes later.

---

## Glue Crawlers: Useful, but Dangerous

Glue crawlers were used only for **initial discovery**, not governance.

Key constraints:

- One crawler per dataset per schema version
- Crawlers target only curated prefixes
- IAM permissions are scoped narrowly

Once schemas stabilize, tables can be managed explicitly and crawlers restricted or removed.

---

## Athena as a Query Boundary

Athena is treated as a read-only engine.

Mitigations against misuse include:

- Partitioned Parquet layouts
- Dedicated workgroups
- Separate result buckets
- No transformations in SQL

Athena queries are consumers of the data contract, not participants in it.

---

## Terraform Architecture and State Strategy

### Module Structure

Terraform was organized into reusable modules:

modules/
s3/
iam/
etl_lambda/
glue_catalog/
athena/


Each module owns **exactly one responsibility**.

### Root Orchestration

The root `main.tf` wires modules together:

- Passes bucket names into Lambda
- Connects S3 notifications to Lambda
- Connects curated storage to Glue
- Connects Glue to Athena

Root never defines resource internals. It only composes contracts.

### State Management

Initially, a single Terraform state was used. The design anticipates splitting into multiple states later:

- `foundation.tfstate` – S3, IAM
- `ingestion.tfstate` – Lambda and notifications
- `catalog.tfstate` – Glue
- `query.tfstate` – Athena

This allows teams to evolve parts independently without state conflicts.

---

## IAM as an Architectural Tool

IAM was used to enforce invariants:

- Lambda can read raw but never write to it
- Lambda can write only to its curated prefix
- Glue can read curated data only
- Athena can read curated data only

Several Glue crawler failures during development highlighted how critical explicit permissions are. Each missing permission surfaced a hidden dependency in Glue’s behavior.

The result is a system where **incorrect behavior is blocked by default**.

---

## Observability and Operability

Minimum observability was built in:

- Structured Lambda logs
- Glue crawler logs in CloudWatch
- Deterministic output paths for replay

Because raw data is immutable, any failure can be replayed safely by re-running Lambda or re-crawling curated data.

---

## Results and Lessons Learned

### What Worked Well

- Clear Terraform module boundaries prevented state drift
- IAM surfaced architectural mistakes early
- Explicit S3 layouts simplified Glue and Athena behavior
- Schema versioning removed fear of change

### Pain Points

- Glue IAM permissions are discovered incrementally and poorly documented
- Lambda packaging requires discipline
- Crawlers are convenient but unpredictable at scale

---

## Conclusion

This project reinforced a core lesson:

> **Infrastructure should enforce correctness, not rely on conventions.**

Terraform shines when used to encode ownership, contracts, and boundaries—not just to create resources.

If you approach serverless data platforms as *event chains*, they will eventually fail in subtle and expensive ways. If you approach them as *contracted systems*, they scale predictably.

---

### Next Steps

If you want to extend this project:

- Add schema version v2 side-by-side
- Automate Glue crawler scheduling safely
- Split Terraform state by domain
- Replace Lambda with Glue ETL without touching storage

All of those are possible because the foundation is stable.

---

*If you’re building data platforms with Terraform, design for failure first. The happy path is easy—the edge cases are where infrastructure earns its keep.*