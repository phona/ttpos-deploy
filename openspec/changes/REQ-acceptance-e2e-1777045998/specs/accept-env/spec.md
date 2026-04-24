## ADDED Requirements

### Requirement: ci-accept-env-up starts ephemeral lab and outputs endpoint JSON

The system SHALL implement a `ci-accept-env-up` Makefile target in `ttpos-deploy` that
starts an ephemeral HTTP server container, waits for it to be healthy, and MUST print a
single JSON object as the last stdout line containing an `endpoint` field (e.g.
`{"endpoint":"http://localhost:<port>","namespace":"<ns>"}`). The implementation MUST NOT
build a Flutter APK or require the Android SDK.

#### Scenario: TTPOSDEPLOY-S1 ci-accept-env-up starts server and prints endpoint JSON

- **GIVEN** `SISYPHUS_NAMESPACE=accept-test` is set
- **WHEN** `make ci-accept-env-up` runs in ttpos-deploy
- **THEN** exit code is 0, last stdout line is valid JSON with `endpoint` and `namespace` keys

#### Scenario: TTPOSDEPLOY-S2 endpoint is reachable on /healthz after env-up

- **GIVEN** `ci-accept-env-up` completed successfully with endpoint `http://localhost:<port>`
- **WHEN** client sends GET `<endpoint>/healthz`
- **THEN** response is 200 with JSON body containing `"status":"ok"`

#### Scenario: TTPOSDEPLOY-S3 ci-accept-env-down tears down idempotently

- **GIVEN** acceptance lab started by `ci-accept-env-up` with `SISYPHUS_NAMESPACE=accept-test`
- **WHEN** `make ci-accept-env-down` is called (even twice in a row)
- **THEN** exit code is 0 and no containers named `ttpos-accept-accept-test` remain

### Requirement: acceptance mock server exposes standard API endpoints

The acceptance mock server MUST expose `/healthz`, `/buildinfo`, and `/api/menu` endpoints.
The server SHALL return JSON responses on all endpoints. These endpoints SHALL be used by
the sisyphus accept-agent to verify the acceptance environment is functional.

#### Scenario: TTPOSDEPLOY-S4 mock server /buildinfo returns service metadata

- **GIVEN** acceptance server running with `BUILD_ID=accept-lab`
- **WHEN** client sends GET `/buildinfo`
- **THEN** response is 200 with JSON containing `build_id`, `go_version`, `service` fields

#### Scenario: TTPOSDEPLOY-S5 mock server /api/menu returns item list

- **GIVEN** acceptance server is running
- **WHEN** client sends GET `/api/menu`
- **THEN** response is 200 with JSON body containing an `items` array with at least one element
