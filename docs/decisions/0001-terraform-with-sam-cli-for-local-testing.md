# 0001: Terraform for all infrastructure, SAM CLI only for local testing

**Status:** Accepted

**Context.** The brief needs API Gateway, Lambda, DynamoDB, Cognito, SNS, S3 and CloudFront. AWS SAM is
built for serverless and has a good local test loop; Terraform is the tool I already know.

**Decision.** Terraform deploys everything, with state in S3 and `use_lockfile` locking. The SAM CLI
(`--hook-name terraform`) is used only to invoke functions locally. SAM templates are not used.

**Consequences.** One source of truth and one state for infrastructure. Lambda packaging is manual
(`archive_file`). Local runs do not test IAM, the JWT authorizer or real AWS services, so those are
tested against the deployed stack.
