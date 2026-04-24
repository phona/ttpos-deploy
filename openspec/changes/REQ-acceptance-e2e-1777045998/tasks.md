# Tasks: REQ-acceptance-e2e-1777045998

## Stage: contract / spec
- [x] Write specs/accept-env/contract.spec.yaml
- [x] Write specs/accept-env/spec.md with TTPOSDEPLOY-S* scenarios

## Stage: implementation
- [x] Add acceptance/mock-server/ (Go HTTP server with /healthz, /buildinfo, /api/menu)
- [x] Add docker-compose.accept.yml
- [x] Add ci-accept-env-up target to Makefile
- [x] Add ci-accept-env-down target to Makefile
- [x] Smoke-test both targets in runner pod

## Stage: PR
- [x] git push feat/REQ-acceptance-e2e-1777045998
- [ ] gh pr create
