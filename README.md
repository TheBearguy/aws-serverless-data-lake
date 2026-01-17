# Serverless Data Lake with Terraform (AWS)

A Terraform-driven, failure-aware serverless data lake on AWS that ingests raw JSON data, transforms it into Parquet, catalogs metadata with Glue, and enables analytics via Athena.

This project is intentionally **Terraform-centric**: infrastructure, boundaries, and contracts are expressed explicitly in code to avoid hidden coupling, state drift, and operational surprises.

---

## Architecture Overview

Raw JSON (S3)
↓ (S3 Event)
Lambda (JSON → Parquet)
↓
Curated Parquet (S3)
↓
Glue Crawler → Glue Data Catalog
↓
Athena Queries


**Core principle:**  
This is not a “pipeline”. It is a **contracted ingestion system** where each component owns a narrow responsibility and Terraform enforces boundaries.

---

## Key Design Goals

- **Immutable raw data** (append-only, replayable)
- **Deterministic transformations**
- **Explicit schema versioning**
- **Clear Terraform state ownership**
- **Least-privilege IAM by default**
- **Cost-aware analytics**

---


## Data Flow

1. **User uploads JSON** to the raw S3 bucket  
2. **S3 event** triggers the Lambda function  
3. Lambda:
   - validates JSON
   - flattens data using a known schema
   - writes Parquet to the curated bucket
4. **Glue crawler** catalogs the curated Parquet data
5. **Athena** queries the dataset using the Glue Data Catalog

---

## S3 Layout

### Raw Bucket (Immutable)
raw/
incoming/
*.json


- Append-only
- Never modified or overwritten
- Used for replay and debugging

### Curated Bucket (Queryable)
curated/
dataset/
schema=0.0.3/
*.parquet


- Parquet only
- Schema version is part of the path
- Matches Glue crawler target exactly

---

## Terraform Modules

### S3 Module
- Creates buckets with clear roles:
  - raw
  - curated
  - athena-results
- Versioning enabled for raw data
- No cross-bucket ambiguity

### IAM Module
- One role per service:
  - Lambda
  - Glue
- Explicit permissions:
  - Lambda: read raw, write curated
  - Glue: read curated, manage catalog
  - Athena: read curated only
- No wildcard S3 access

### Lambda Module
- Stateless, deterministic ETL
- Receives all runtime configuration via environment variables:
  - `RAW_BUCKET`
  - `CURATED_BUCKET`
  - `CURATED_PREFIX`
  - `SCHEMA_VERSION`
- No hardcoded paths in code

### Glue Catalog Module
- One database per domain
- One crawler per dataset + schema version
- Crawler scoped to a single curated prefix

### Athena Module
- Dedicated workgroup
- Isolated result bucket
- Enforced query configuration

---

## Terraform State Strategy

Current setup uses a single state for simplicity.

Planned evolution:

- `foundation.tfstate`  
  S3, IAM, logging
- `ingestion.tfstate`  
  Lambda + S3 notifications
- `catalog.tfstate`  
  Glue databases and crawlers
- `query.tfstate`  
  Athena workgroups

This allows teams to evolve parts independently without state conflicts.

---

## Deployment Workflow

1. Build Lambda artifact:
lambda/dist/etl.zip

2. Initialize Terraform:
```bash
terraform init
```

3. Validate configuration
```bash
terraform validate
terraform plan
```

4. Apply infrastructure
```bash
terraform apply
```

5. Upload a JSON file to the raw bucket

6. Run the Glue crawler (manual or scheduled)

7. Query data using Athena


### Operational Invariants

These rules are enforced by design:

- Raw data is never overwritten

- Lambda cannot write to the raw bucket

- Glue cannot read raw data

- Athena never queries raw data

- Terraform does not manage data, only infrastructure

If any of these invariants break, the architecture must be revisited.
--- 

### Common Pitfalls (Avoided Here)

- Flattening JSON without a schema contract
- Letting Glue crawlers auto-mutate schemas
- Writing Parquet to ad-hoc paths
- Mixing raw and curated data
- Using Athena for transformations
- Granting broad IAM permissions “just to make it work”

--- 

### Observability

- CloudWatch logs for Lambda and Glue crawlers
- Deterministic S3 paths for replay
- Failures are visible and recoverable without data loss

--- 

### Future Enhancements

- Scheduled Glue crawler runs (EventBridge)
- Lambda → Glue ETL migration
- Partition evolution for large datasets
- CI/CD for Terraform and Lambda artifacts