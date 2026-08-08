//go:build openharmony
// +build openharmony

package openp2p

import (
	"runtime"
)

var defaultInstallPath = ""

const defaultBinName = "openp2p-opl"

func getOsName() string {
	if runtime.GOOS == "openharmony" || isOpenHarmonyPlatform() {
		return "OpenHarmony"
	}
	return "Linux"
}

func setRLimit() error {
	// The VPN extension is not a standalone daemon and OHOS controls the
	// process resource limits. Keep this hook for the shared startup path.
	return nil
}

// Firewall and route ownership belong to the OHOS VPN framework.
func setFirewall() {}
