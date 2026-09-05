package openp2p

import (
	"testing"
	"time"
)

func TestP2PAppCloseStopsWorkers(t *testing.T) {
	app := &p2pApp{}
	app.Init(2)
	started := make(chan struct{})
	app.goWorker(func() {
		close(started)
		app.wait(time.Hour)
	})
	<-started

	closed := make(chan struct{})
	go func() {
		app.Close()
		app.Close()
		close(closed)
	}()
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("p2p app workers did not stop")
	}
}
