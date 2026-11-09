# 0007: Plain React + Amplify UI Authenticator, hosted on private S3 behind CloudFront

**Status:** Accepted (replaces the Phase 1 idea of react-admin + ra-auth-cognito)

**Context.** The brief allows an open-source front end. react-admin with ra-auth-cognito fitted the CRUD
shape, but that auth package is updated rarely, and version mismatches were the biggest schedule risk.

**Decision.**
- React (Vite) with the open-source Amplify UI `Authenticator` for sign-in (SRP, so the password is
  never sent). Sign-up is hidden; only admins create accounts.
- The app sends the Cognito **access token** to the API. The UI reads `cognito:groups` from the ID token
  only to decide what to show; the API enforces every rule.
- Hosting: private S3 bucket, read only by one CloudFront distribution through Origin Access Control.
  HTTPS only, AWS-managed security headers, 403/404 mapped to `index.html` for the single-page app.
- Hashed build files are cached for a year; `index.html` is revalidated on every visit and invalidated
  on deploy, so users get a new release immediately.
- CORS on the API and the attachments bucket allows only the CloudFront origin (plus localhost:5173
  for development).

**Consequences.** No hosted-UI redirects or callback URLs to configure. The default `*.cloudfront.net`
domain is used; a custom domain would need an ACM certificate in us-east-1 and DNS. Configuration is
baked in at build time, so a new environment needs a rebuild (the deploy script does this).
