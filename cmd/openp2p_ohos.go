//go:build openharmony
// +build openharmony

package main

/*
#include <stdint.h>
*/
import "C"

import (
	"sync"
	"unsafe"

	op2p "openp2p/core"
)

var (
	coreMu            sync.Mutex
	coreRunning       bool
	coreStopRequested bool
	coreState         int32
	coreLastError     string
)

const (
	coreStateStopped  int32 = 0
	coreStateStarting int32 = 1
	coreStateRunning  int32 = 2
	coreStateFailed   int32 = 3
)

func copyCString(data *C.char, capacity C.int32_t, value string) C.int32_t {
	if data == nil || capacity <= 0 {
		return 0
	}
	buffer := unsafe.Slice((*byte)(unsafe.Pointer(data)), int(capacity))
	if len(value) >= len(buffer) {
		value = value[:len(buffer)-1]
	}
	copy(buffer, value)
	buffer[len(value)] = 0
	return C.int32_t(len(value))
}

// OpenP2PStart starts the same in-process core used by Android. It returns
// after scheduling the login worker; the native caller observes connection
// progress through OpenP2PGetStatus/OpenP2PGetLastError.
//
//export OpenP2PStart
func OpenP2PStart(baseDir *C.char, token *C.char, shareBandwidth C.int64_t, logLevel C.int64_t) C.int32_t {
	coreMu.Lock()
	if coreRunning {
		coreMu.Unlock()
		return 1
	}

	base := C.GoString(baseDir)
	accessToken := C.GoString(token)
	if base == "" || accessToken == "" {
		coreState = coreStateFailed
		coreLastError = "OpenP2PStart received an empty base directory or token"
		coreMu.Unlock()
		return 0
	}
	coreStopRequested = false
	coreRunning = true
	coreState = coreStateStarting
	coreLastError = ""
	coreMu.Unlock()

	go func() {
		network := op2p.RunAsModule(base, accessToken, int(shareBandwidth), int(logLevel))
		if network == nil {
			op2p.StopModule()
			coreMu.Lock()
			coreRunning = false
			if coreStopRequested {
				coreState = coreStateStopped
				coreLastError = ""
			} else {
				coreState = coreStateFailed
				coreLastError = "OpenP2P RunAsModule failed; check the token, config, and login log"
			}
			coreMu.Unlock()
			return
		}
		coreMu.Lock()
		stopRequested := coreStopRequested
		if stopRequested {
			coreRunning = false
			coreState = coreStateStopped
			coreLastError = ""
		} else {
			coreState = coreStateRunning
			coreLastError = ""
		}
		coreMu.Unlock()
		if stopRequested {
			op2p.StopModule()
		}
	}()
	return 1
}

// OpenP2PStop stops the in-process core without terminating the host ability.
//
//export OpenP2PStop
func OpenP2PStop() {
	coreMu.Lock()
	coreStopRequested = true
	coreRunning = false
	coreState = coreStateStopped
	coreLastError = ""
	coreMu.Unlock()
	op2p.StopModule()
}

// OpenP2PGetStatus returns the asynchronous core state:
// 0=stopped, 1=starting, 2=running, 3=failed.
//
//export OpenP2PGetStatus
func OpenP2PGetStatus() C.int32_t {
	coreMu.Lock()
	defer coreMu.Unlock()
	return C.int32_t(coreState)
}

// OpenP2PGetLastError copies the last asynchronous startup error into data.
//
//export OpenP2PGetLastError
func OpenP2PGetLastError(data *C.char, capacity C.int32_t) C.int32_t {
	coreMu.Lock()
	lastError := coreLastError
	coreMu.Unlock()
	return copyCString(data, capacity, lastError)
}

// OpenP2PGetSDWANConfig fills data with the JSON VPN configuration generated
// by the core. It blocks until the server sends a new configuration.
//
//export OpenP2PGetSDWANConfig
func OpenP2PGetSDWANConfig(data *C.uchar, capacity C.int32_t) C.int32_t {
	if data == nil || capacity <= 0 {
		return 0
	}
	buffer := unsafe.Slice((*byte)(unsafe.Pointer(data)), int(capacity))
	return C.int32_t(op2p.GetOhosSDWANConfig(buffer))
}

// OpenP2PGetNodeName fills data with the local OpenP2P node name.
//
//export OpenP2PGetNodeName
func OpenP2PGetNodeName(data *C.char, capacity C.int32_t) C.int32_t {
	if data == nil || capacity <= 0 {
		return 0
	}
	name := op2p.GetOhosNodeName()
	buffer := unsafe.Slice((*byte)(unsafe.Pointer(data)), int(capacity))
	if len(name) >= len(buffer) {
		name = name[:len(buffer)-1]
	}
	copy(buffer, name)
	buffer[len(name)] = 0
	return C.int32_t(len(name))
}

// OpenP2PReadTun injects a packet read from the OHOS VPN fd.
//
//export OpenP2PReadTun
func OpenP2PReadTun(data *C.uchar, length C.int32_t) {
	if data == nil || length <= 0 {
		return
	}
	buffer := unsafe.Slice((*byte)(unsafe.Pointer(data)), int(length))
	op2p.OhosRead(buffer, int(length))
}

// OpenP2PWriteTun copies the next packet emitted by the core into data.
//
//export OpenP2PWriteTun
func OpenP2PWriteTun(data *C.uchar, capacity C.int32_t, timeoutMs C.int32_t) C.int32_t {
	if data == nil || capacity <= 0 {
		return 0
	}
	buffer := unsafe.Slice((*byte)(unsafe.Pointer(data)), int(capacity))
	return C.int32_t(op2p.OhosWrite(buffer, int(timeoutMs)))
}

func main() {}
