//go:build openharmony
// +build openharmony

package openp2p

import "testing"

func TestOhosTunStopCancelsInstanceQueues(t *testing.T) {
	tun := &optun{done: make(chan struct{})}
	if err := tun.Start("10.0.0.1/24", &SDWANInfo{}); err != nil {
		t.Fatal(err)
	}

	OhosRead([]byte{1, 2, 3}, 3)
	bufs := make([][]byte, 1)
	sizes := make([]int, 1)
	if n, err := tun.Read(bufs, sizes, 0); err != nil || n != 1 || sizes[0] != 3 {
		t.Fatalf("Read() = %d, %v, size=%d", n, err, sizes[0])
	}

	if err := tun.Stop(); err != nil {
		t.Fatal(err)
	}
	if err := tun.Stop(); err != nil {
		t.Fatalf("second Stop() = %v", err)
	}
	if _, err := tun.Read(bufs, sizes, 0); err == nil {
		t.Fatal("Read() after Stop() should be cancelled")
	}

	OhosRead([]byte{4}, 1)
}
