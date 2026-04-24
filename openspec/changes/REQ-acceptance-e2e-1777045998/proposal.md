# Proposal: Sisyphus E2E Acceptance Environment

## Problem

Sisyphus `accept` stage calls `make ci-accept-env-up` in the integration repo, but
`ttpos-deploy` had no such target. Acceptance could not run end-to-end.

Additionally, the user explicitly does not want to build the Flutter APK inside the acceptance
environment — that would require the Android SDK, Gradle, and ~15 min. Instead, acceptance
tests target the Go server HTTP API; Flutter correctness is verified earlier in staging via
`flutter test`.

## Solution

Add `ci-accept-env-up` / `ci-accept-env-down` Makefile targets to `ttpos-deploy` that:

1. Build (or pull) a minimal Go HTTP server image using Docker (fast: ~15s cached).
2. Start it with Docker Compose on a dynamic ephemeral port.
3. Wait for `/healthz` to be healthy.
4. Print the sisyphus endpoint JSON as the final stdout line.
5. Tear down idempotently on `ci-accept-env-down`.

When `ACCEPT_IMAGE` env var is set (e.g. `ghcr.io/phona/ttpos-server-go:REQ-x-sha-abc`),
the pre-built production image is used directly — no build step. This is the production path
once `ttpos-server-go` CI is wired up.

## Non-Goals

- No APK build. Flutter mobile tests run via `flutter test` in staging, not acceptance.
- No Kubernetes / helm in the acceptance env. Docker Compose is sufficient and avoids
  kubectl dependency in the runner pod.
