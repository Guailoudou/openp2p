package openp2p

import (
	"sync"

	"github.com/openp2p-cn/wireguard-go/tun"
)

const optunMTU = 1420

var AndroidSDWANConfig chan []byte
var preAndroidSDWANConfig string

type optun struct {
	tunName string
	dev     tun.Device
	done    chan struct{}
	stop    sync.Once
	loops   sync.WaitGroup
	readCh  chan []byte
	writeCh chan []byte
}

func (t *optun) stopped() <-chan struct{} { return t.done }

func init() {
	AndroidSDWANConfig = make(chan []byte, 1)
}
