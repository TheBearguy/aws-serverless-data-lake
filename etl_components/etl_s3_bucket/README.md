# S3 Module

This module creates a secure S3 bucket with:
- encryption enforced
- public access blocked
- versioning

## What this module does NOT do
- No event notifications
- No IAM permissions
- No consumer assumptions

Each bucket must be instantiated separately for each purpose
(raw, curated, athena-results).