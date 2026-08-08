//go:build openharmony
// +build openharmony

package openp2p

import "time"

// OpenHarmony exposes the VPN interface fd to the application. The Go core
// uses the same packet-queue contract as Android; the OHOS NAPI layer feeds
// these queues from the VpnConnection fd.
const (
	tunIfaceName    = "optun"
	PIHeaderSize    = 0
	ReadTunBuffSize = 2048
	ReadTunBuffNum  = 16
)

var OhosReadTun chan []byte
var OhosWriteTun chan []byte

func (t *optun) Start(localAddr string, detail *SDWANInfo) error { return nil }

func (t *optun) Read(bufs [][]byte, sizes []int, offset int) (n int, err error) {
	bufs[0] = <-OhosReadTun
	sizes[0] = len(bufs[0])
	return 1, nil
}

func (t *optun) Write(bufs [][]byte, offset int) (int, error) {
	OhosWriteTun <- bufs[0]
	return len(bufs[0]), nil
}

// OhosRead injects a packet read from the OpenHarmony VPN interface.
func OhosRead(data []byte, length int) {
	if length < 0 || length > len(data) {
		return
	}
	buf := make([]byte, length)
	copy(buf, data[:length])
	OhosReadTun <- buf
}

// OhosWrite copies the next packet produced by the Go core into data.
func OhosWrite(data []byte, timeoutMs int) int {
	timeout := time.Duration(timeoutMs) * time.Millisecond
	select {
	case packet := <-OhosWriteTun:
		if len(packet) > len(data) {
			gLog.e("OpenHarmony write packet too large %d", len(packet))
			return 0
		}
		copy(data, packet)
		return len(packet)
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

// The VPN framework owns the interface address and routes on OHOS.
func setTunAddr(ifname, localAddr, remoteAddr string, wintun interface{}) error { return nil }
func addRoute(dst, gw, ifname string) error                                     { return nil }
func delRoute(dst, gw string) error                                             { return nil }
func delRoutesByGateway(gateway string) error                                   { return nil }

func init() {
	OhosReadTun = make(chan []byte, 1000)
	OhosWriteTun = make(chan []byte, 1000)
}
