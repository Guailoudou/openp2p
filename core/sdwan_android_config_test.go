package openp2p

import "testing"

func TestCompareAndroidSDWANConfigDetectsRemoteChanges(t *testing.T) {
	base := `{"id":1,"name":"net","gateway":"10.2.3.254/24","enable":1,"mtu":1420,"Nodes":[{"name":"phone","ip":"10.2.3.8"}]}`
	tests := []string{
		`{"id":1,"name":"net","gateway":"10.2.3.254/24","enable":0,"mtu":1420,"Nodes":[{"name":"phone","ip":"10.2.3.8"}]}`,
		`{"id":1,"name":"net","gateway":"10.2.3.254/24","enable":1,"mtu":1280,"Nodes":[{"name":"phone","ip":"10.2.3.8"}]}`,
		`{"id":1,"name":"net","gateway":"10.2.3.254/24","enable":1,"mtu":1420,"Nodes":[{"name":"phone","ip":"10.2.3.9"}]}`,
	}
	for _, changed := range tests {
		if compareAndroidSDWANConfig(base, changed) {
			t.Fatalf("configuration change was ignored: %s", changed)
		}
	}
	if !compareAndroidSDWANConfig(base, base) {
		t.Fatal("identical configurations should compare equal")
	}
}
