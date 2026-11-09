# 0002: API Gateway HTTP API (v2) instead of REST API (v1)

**Status:** Accepted

**Context.** The brief asks for RESTful APIs. API Gateway offers HTTP APIs and REST APIs.

**Decision.** Use an HTTP API with a built-in JWT authorizer for Cognito.

**Consequences.** Lower cost per request and simpler configuration. "RESTful" describes the API design,
which HTTP APIs support fully. Not available: usage plans, API keys, request validation and direct WAF
attachment, none of which this project needs. Input is validated in the Lambdas instead.
