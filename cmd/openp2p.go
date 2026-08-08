//go:build !openharmony
// +build !openharmony

package main

import (
	op2p "openp2p/core"
)

func main() {
	op2p.Run()
}
