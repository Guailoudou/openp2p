package openp2p

import (
	"os"
	"path/filepath"
	"testing"
)

func TestShouldUseNodeCandidate(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")

	if !shouldUseNodeCandidate(path) {
		t.Fatal("missing config.json should accept the device node candidate")
	}

	for _, content := range []string{
		`{}`,
		`{"network":{}}`,
		`{"network":{"Node":""}}`,
		`{"network":{"Node":"   "}}`,
	} {
		if err := os.WriteFile(path, []byte(content), 0600); err != nil {
			t.Fatal(err)
		}
		if !shouldUseNodeCandidate(path) {
			t.Fatalf("config %s should accept the device node candidate", content)
		}
	}

	if err := os.WriteFile(path, []byte(`{"network":{"Node":"existing-node"}}`), 0600); err != nil {
		t.Fatal(err)
	}
	if shouldUseNodeCandidate(path) {
		t.Fatal("an existing non-empty node must not be overwritten")
	}

	if err := os.WriteFile(path, []byte(`{invalid`), 0600); err != nil {
		t.Fatal(err)
	}
	if shouldUseNodeCandidate(path) {
		t.Fatal("a malformed config must not be treated as an empty node")
	}
}

func TestNormalizeNodeCandidate(t *testing.T) {
	if got := normalizeNodeCandidate("  HUAWEI Mate 60 Pro  "); got != "HUAWEI-Mate-60-Pro" {
		t.Fatalf("unexpected normalized node: %q", got)
	}
	if got := normalizeNodeCandidate("Pixel 9"); got != "Pixel-90" {
		t.Fatalf("short node was not padded to the minimum length: %q", got)
	}
	if got := normalizeNodeCandidate("123456789012345678901234567890123456"); len([]rune(got)) != 31 {
		t.Fatalf("long node was not truncated to 31 characters: %q", got)
	}
}
