//go:build contract
// +build contract

// Contract tests for REQ-acceptance-e2e-1777045998 capability: accept-env
// Scenarios: TTPOSDEPLOY-S1 through TTPOSDEPLOY-S5
// Black-box only — no business code imported.
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

const (
	sharedNamespace = "accept-contract-ci"
	s3Namespace     = "accept-contract-s3"
	s1Namespace     = "accept-contract-s1"
)

// testEndpoint is set by TestMain from the last-line JSON of ci-accept-env-up.
var testEndpoint string

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

// runShell executes a shell command and returns combined output + exit code.
func runShell(command string) (string, int) {
	cmd := exec.Command("bash", "-c", command)
	out, err := cmd.CombinedOutput()
	if err == nil {
		return string(out), 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return string(out), ee.ExitCode()
	}
	return string(out), -1
}

// lastLine returns the last non-empty line from s.
func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.TrimSpace(lines[i]) != "" {
			return strings.TrimSpace(lines[i])
		}
	}
	return ""
}

// toIPv4Endpoint replaces "localhost" with "127.0.0.1" so Go's HTTP client
// doesn't try IPv6 first when Docker only binds on IPv4.
func toIPv4Endpoint(ep string) string {
	return strings.ReplaceAll(ep, "://localhost:", "://127.0.0.1:")
}

// lastJSONLine finds the last line in s that looks like a JSON object (starts with '{').
// Falls back to lastLine if no such line exists.
func lastJSONLine(s string) string {
	lines := strings.Split(s, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		t := strings.TrimSpace(lines[i])
		if strings.HasPrefix(t, "{") {
			return t
		}
	}
	return lastLine(s)
}

// TestMain starts the shared acceptance env, runs all tests, then tears down.
func TestMain(m *testing.M) {
	out, code := runMake("ci-accept-env-up",
		"SISYPHUS_NAMESPACE="+sharedNamespace)
	if code != 0 {
		fmt.Fprintf(os.Stderr,
			"[TestMain] ci-accept-env-up failed (exit %d):\n%s\n", code, out)
		os.Exit(1)
	}
	last := lastJSONLine(out)
	var j map[string]any
	if err := json.Unmarshal([]byte(last), &j); err == nil {
		if ep, ok := j["endpoint"].(string); ok {
			testEndpoint = toIPv4Endpoint(ep)
		}
	}
	result := m.Run()
	runMake("ci-accept-env-down", "SISYPHUS_NAMESPACE="+sharedNamespace)
	os.Exit(result)
}

// Scenario TTPOSDEPLOY-S1: ci-accept-env-up exits 0 and last stdout line is JSON with endpoint+namespace.
func TestS1_EnvUpExitsZeroAndOutputsEndpointJSON(t *testing.T) {
	out, code := runMake("ci-accept-env-up",
		"SISYPHUS_NAMESPACE="+s1Namespace)
	defer runMake("ci-accept-env-down", "SISYPHUS_NAMESPACE="+s1Namespace)

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
	if testEndpoint == "" {
		t.Fatal("testEndpoint not set; shared env-up likely failed in TestMain")
	}
	resp, err := http.Get(testEndpoint + "/healthz")
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
	// Start an independent env for this test.
	_, _ = runMake("ci-accept-env-up", "SISYPHUS_NAMESPACE="+s3Namespace)

	// First teardown.
	_, code1 := runMake("ci-accept-env-down", "SISYPHUS_NAMESPACE="+s3Namespace)
	if code1 != 0 {
		t.Errorf("first ci-accept-env-down exit %d, want 0", code1)
	}
	// Second teardown (must be idempotent).
	_, code2 := runMake("ci-accept-env-down", "SISYPHUS_NAMESPACE="+s3Namespace)
	if code2 != 0 {
		t.Errorf("second ci-accept-env-down exit %d, want 0", code2)
	}
	// Verify no container with this namespace remains.
	out, _ := runShell(fmt.Sprintf(
		"docker ps -a --filter name=ttpos-accept-%s --format '{{.Names}}'", s3Namespace))
	if strings.TrimSpace(out) != "" {
		t.Errorf("container still present after env-down: %s", out)
	}
}

// Scenario TTPOSDEPLOY-S4: /buildinfo returns 200 with build_id, go_version, service fields.
func TestS4_BuildinfoReturnsMetadataFields(t *testing.T) {
	if testEndpoint == "" {
		t.Fatal("testEndpoint not set; shared env-up likely failed in TestMain")
	}
	resp, err := http.Get(testEndpoint + "/buildinfo")
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
	if testEndpoint == "" {
		t.Fatal("testEndpoint not set; shared env-up likely failed in TestMain")
	}
	resp, err := http.Get(testEndpoint + "/api/menu")
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
