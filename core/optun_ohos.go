//go:build openharmony
// +build openharmony

package openp2p

import (
	"encoding/json"
	"errors"
	"io"
	"sync"
	"sync/atomic"
	"time"
)

// OpenHarmony exposes the VPN interface fd to the application. The Go core
// uses the same packet-queue contract as Android; the OHOS NAPI layer feeds
// these queues from the VpnConnection fd.
const (
	tunIfaceName    = "optun"
	PIHeaderSize    = 0
	ReadTunBuffSize = 2048
	ReadTunBuffNum  = 16
)

var (
	ohosTunMu         sync.RWMutex
	ohosTun           *optun
	ohosGeneration    atomic.Uint64
	ohosLastPacketIn  atomic.Int64
	ohosLastPacketOut atomic.Int64
)

func (t *optun) Start(localAddr string, detail *SDWANInfo) error {
	t.tunName = tunIfaceName
	t.readCh = make(chan []byte, 1000)
	t.writeCh = make(chan []byte, 1000)
	ohosTunMu.Lock()
	if ohosTun != nil {
		ohosTunMu.Unlock()
		return errors.New("OpenHarmony TUN generation is still stopping")
	}
	ohosTun = t
	ohosGeneration.Add(1)
	ohosTunMu.Unlock()
	return nil
}

func (t *optun) Stop() error {
	t.stop.Do(func() {
		close(t.done)
	})
	t.loops.Wait()
	ohosTunMu.Lock()
	if ohosTun == t {
		ohosTun = nil
		ohosGeneration.Add(1)
	}
	ohosTunMu.Unlock()
	return nil
}

func (t *optun) Read(bufs [][]byte, sizes []int, offset int) (n int, err error) {
	select {
	case packet := <-t.readCh:
		bufs[0] = packet
		sizes[0] = len(packet)
		return 1, nil
	case <-t.done:
		return 0, io.ErrClosedPipe
	}
}

func (t *optun) Write(bufs [][]byte, offset int) (int, error) {
	select {
	case t.writeCh <- bufs[0]:
		return len(bufs[0]), nil
	case <-t.done:
		return 0, io.ErrClosedPipe
	}
}

// OhosRead injects a packet read from the OpenHarmony VPN interface.
func OhosRead(data []byte, length int) {
	if length < 0 || length > len(data) {
		return
	}
	buf := make([]byte, length)
	copy(buf, data[:length])
	ohosTunMu.RLock()
	t := ohosTun
	ohosTunMu.RUnlock()
	if t == nil {
		return
	}
	select {
	case t.readCh <- buf:
		ohosLastPacketIn.Store(time.Now().UnixMilli())
	case <-t.done:
	default:
		gLog.w("OpenHarmony read queue full, dropping packet")
	}
}

// OhosWrite copies the next packet produced by the Go core into data.
func OhosWrite(data []byte, timeoutMs int) int {
	timeout := time.Duration(timeoutMs) * time.Millisecond
	ohosTunMu.RLock()
	t := ohosTun
	ohosTunMu.RUnlock()
	if t == nil {
		return 0
	}
	select {
	case packet := <-t.writeCh:
		if len(packet) > len(data) {
			gLog.e("OpenHarmony write packet too large %d", len(packet))
			return 0
		}
		copy(data, packet)
		ohosLastPacketOut.Store(time.Now().UnixMilli())
		return len(packet)
	case <-t.done:
		return 0
	case <-time.After(timeout):
		return 0
	}
}

// GetOhosSDWANConfig blocks until the core receives the current VPN config.
func GetOhosSDWANConfig(data []byte) int {
	packet := <-AndroidSDWANConfig
	if len(packet) > len(data) {
		return 0
	}
	copy(data, packet)
	gLog.i("OhosSDWANConfig=%s", packet)
	return len(packet)
}

func GetOhosNodeName() string { return gConf.Network.Node }

type OhosHealth struct {
	CoreAlive       bool   `json:"coreAlive"`
	ControlOnline   bool   `json:"controlOnline"`
	Generation      uint64 `json:"generation"`
	LastPacketInMs  int64  `json:"lastPacketInMs"`
	LastPacketOutMs int64  `json:"lastPacketOutMs"`
}

func GetOhosHealth() string {
	health := OhosHealth{
		CoreAlive:       IsModuleRunning(),
		Generation:      ohosGeneration.Load(),
		LastPacketInMs:  ohosLastPacketIn.Load(),
		LastPacketOutMs: ohosLastPacketOut.Load(),
	}
	networkMu.Lock()
	if GNetwork != nil {
		health.ControlOnline = GNetwork.online.Load()
	}
	networkMu.Unlock()
	data, _ := json.Marshal(health)
	return string(data)
}

// The VPN framework owns the interface address and routes on OHOS.
func setTunAddr(ifname, localAddr, remoteAddr string, wintun interface{}) error { return nil }
func addRoute(dst, gw, ifname string) error                                     { return nil }
func delRoute(dst, gw string) error                                             { return nil }
func delRoutesByGateway(gateway string) error                                   { return nil }
