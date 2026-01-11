# Glue Catalog Module

This module provisions Glue metadata for a single curated dataset.

## Responsibilities
- Glue database
- Glue crawler
- Table registration for Parquet data

## Out of Scope
- Data transformation
- Schema evolution
- Partition repair
- Athena configuration

Each module instance should map to exactly one dataset
and one schema version.