//go:build contract
// +build contract

// Contract tests for REQ-acceptance-e2e-1777045998 capability: accept-env
// Scenarios: TTPOSDEPLOY-S1 through TTPOSDEPLOY-S5
// Black-box only — no business code imported.
//
// Each test manages its own env-up/env-down lifecycle.
// Tests run sequentially (no t.Parallel) to avoid docker-compose project-name
// collisions caused by the Makefile not using the -p flag.
package contract

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// repoRoot returns the ttpos-deploy repo root (two levels up from tests/integration/).
func repoRoot() string {
	abs, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		panic(err)
	}
	return abs
}

// runMake executes `make <args...>` in the repo root and returns combined output + exit code.
func runMake(args ...string) (string, int) {
	cmd := exec.Command("make", args...)
	cmd.Dir = repoRoot()
	out, err := cmd.CombinedOutput()
	if err == nil {
		return string(out), 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return string(out), ee.ExitCode()
	}
	return string(out), -1
}

// runShell executes a shell command and returns combined output.
func runShell(command string) string {
	cmd := exec.Command("bash", "-c", command)
	out, _ := cmd.CombinedOutput()
	return string(out)
}

// lastJSONLine finds the last line in s that starts with '{' (JSON object).
// Falls back to the last non-empty line if no JSON line is found.
func lastJSONLine(s string) string {
	lines := strings.Split(s, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		t := strings.TrimSpace(lines[i])
		if strings.HasPrefix(t, "{") {
			return t
		}
	}
	// fallback: last non-empty line
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.TrimSpace(lines[i]) != "" {
			return strings.TrimSpace(lines[i])
		}
	}
	return ""
}

// toIPv4Endpoint replaces "localhost" with "127.0.0.1" so Go's HTTP client
// doesn't prefer IPv6 when Docker only binds on IPv4.
func toIPv4Endpoint(ep string) string {
	return strings.ReplaceAll(ep, "://localhost:", "://127.0.0.1:")
}

// envUp calls ci-accept-env-up with the given namespace and returns (endpoint, output, exit code).
func envUp(ns string) (endpoint string, out string, code int) {
	out, code = runMake("ci-accept-env-up", "SISYPHUS_NAMESPACE="+ns)
	if code != 0 {
		return "", out, code
	}
	last := lastJSONLine(out)
	var j map[string]any
	if err := json.Unmarshal([]byte(last), &j); err == nil {
		if ep, ok := j["endpoint"].(string); ok {
			endpoint = toIPv4Endpoint(ep)
		}
	}
	return endpoint, out, 0
}

// envDown calls ci-accept-env-down with the given namespace and returns exit code.
func envDown(ns string) int {
	_, code := runMake("ci-accept-env-down", "SISYPHUS_NAMESPACE="+ns)
	return code
}

// Scenario TTPOSDEPLOY-S1: ci-accept-env-up exits 0 and last stdout line is JSON with endpoint+namespace.
func TestS1_EnvUpExitsZeroAndOutputsEndpointJSON(t *testing.T) {
	const ns = "accept-s1"
	out, code := runMake("ci-accept-env-up", "SISYPHUS_NAMESPACE="+ns)
	defer envDown(ns)

	if code != 0 {
		t.Fatalf("ci-accept-env-up exit %d; output:\n%s", code, out)
	}
	last := lastJSONLine(out)
	var j map[string]any
	if err := json.Unmarshal([]byte(last), &j); err != nil {
		t.Fatalf("no valid JSON object line found in output: %q; err: %v", last, err)
	}
	for _, key := range []string{"endpoint", "namespace"} {
		if _, ok := j[key]; !ok {
			t.Errorf("JSON missing required field: %s", key)
		}
	}
}

// Scenario TTPOSDEPLOY-S2: endpoint /healthz returns 200 with {"status":"ok"}.
func TestS2_HealthzReturns200WithStatusOK(t *testing.T) {
	const ns = "accept-s2"
	endpoint, out, code := envUp(ns)
	defer envDown(ns)
	if code != 0 {
		t.Fatalf("ci-accept-env-up exit %d:\n%s", code, out)
	}
	if endpoint == "" {
		t.Fatalf("could not parse endpoint from output:\n%s", out)
	}

	resp, err := http.Get(endpoint + "/healthz")
	if err != nil {
		t.Fatalf("GET /healthz: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("want 200, got %d", resp.StatusCode)
	}
	var body map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("/healthz response not valid JSON: %v", err)
	}
	st, ok := body["status"].(string)
	if !ok || st != "ok" {
		t.Errorf("want status=ok, got %v", body["status"])
	}
}

// Scenario TTPOSDEPLOY-S3: ci-accept-env-down exits 0 when called twice (idempotent) and no container remains.
func TestS3_EnvDownIdempotent(t *testing.T) {
	const ns = "accept-s3"
	_, _, _ = envUp(ns)

	if c := envDown(ns); c != 0 {
		t.Errorf("first ci-accept-env-down exit %d, want 0", c)
	}
	if c := envDown(ns); c != 0 {
		t.Errorf("second ci-accept-env-down exit %d, want 0", c)
	}
	containers := runShell(fmt.Sprintf(
		"docker ps -a --filter name=ttpos-accept-%s --format '{{.Names}}'", ns))
	if strings.TrimSpace(containers) != "" {
		t.Errorf("container still present after env-down: %s", containers)
	}
}

// Scenario TTPOSDEPLOY-S4: /buildinfo returns 200 with build_id, go_version, service fields.
func TestS4_BuildinfoReturnsMetadataFields(t *testing.T) {
	const ns = "accept-s4"
	endpoint, out, code := envUp(ns)
	defer envDown(ns)
	if code != 0 {
		t.Fatalf("ci-accept-env-up exit %d:\n%s", code, out)
	}
	if endpoint == "" {
		t.Fatalf("could not parse endpoint from output:\n%s", out)
	}

	resp, err := http.Get(endpoint + "/buildinfo")
	if err != nil {
		t.Fatalf("GET /buildinfo: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("want 200, got %d", resp.StatusCode)
	}
	var body map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("/buildinfo response not valid JSON: %v", err)
	}
	for _, field := range []string{"build_id", "go_version", "service"} {
		if _, ok := body[field]; !ok {
			t.Errorf("missing required field: %s", field)
		}
	}
}

// Scenario TTPOSDEPLOY-S5: /api/menu returns 200 with JSON body containing items array with ≥1 element.
func TestS5_MenuReturnsNonEmptyItemsArray(t *testing.T) {
	const ns = "accept-s5"
	endpoint, out, code := envUp(ns)
	defer envDown(ns)
	if code != 0 {
		t.Fatalf("ci-accept-env-up exit %d:\n%s", code, out)
	}
	if endpoint == "" {
		t.Fatalf("could not parse endpoint from output:\n%s", out)
	}

	resp, err := http.Get(endpoint + "/api/menu")
	if err != nil {
		t.Fatalf("GET /api/menu: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Errorf("want 200, got %d", resp.StatusCode)
	}
	var body map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatalf("/api/menu response not valid JSON: %v", err)
	}
	items, ok := body["items"]
	if !ok {
		t.Fatal("response missing required field: items")
	}
	arr, ok := items.([]any)
	if !ok {
		t.Fatalf("items field is not an array, got %T", items)
	}
	if len(arr) < 1 {
		t.Errorf("items array is empty; want at least 1 element")
	}
}

// TestMain exists only to ensure a clean environment before running tests.
// It does NOT start a shared server — each test manages its own lifecycle.
func TestMain(m *testing.M) {
	os.Exit(m.Run())
}
