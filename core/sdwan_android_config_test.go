package openp2p

import "testing"

func TestDecodeSDWANInfoEnableSemantics(t *testing.T) {
	tests := []struct {
		name string
		json string
		want int32
	}{
		{name: "missing defaults to enabled", json: `{"gateway":"10.2.3.254/24"}`, want: 1},
		{name: "explicit zero disables", json: `{"gateway":"10.2.3.254/24","enable":0}`, want: 0},
		{name: "explicit one enables", json: `{"gateway":"10.2.3.254/24","enable":1}`, want: 1},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := decodeSDWANInfo([]byte(test.json))
			if err != nil {
				t.Fatalf("decodeSDWANInfo() error = %v", err)
			}
			if got.Enable != test.want {
				t.Fatalf("Enable = %d, want %d", got.Enable, test.want)
			}
		})
	}
}

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
	withoutEnable := `{"id":1,"name":"net","gateway":"10.2.3.254/24","mtu":1420,"Nodes":[{"name":"phone","ip":"10.2.3.8"}]}`
	if !compareAndroidSDWANConfig(base, withoutEnable) {
		t.Fatal("missing enable and explicit enable=1 should be equivalent")
	}
}
