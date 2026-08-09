package openp2p

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

var GNetwork *P2PNetwork

func Run() {
	rand.Seed(time.Now().UnixNano())
	baseDir := filepath.Dir(os.Args[0])
	os.Chdir(baseDir) // for system service
	gLog = NewLogger(baseDir, ProductName, LvDEBUG, 1024*1024, LogFile|LogConsole)
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "version", "-v", "--version":
			fmt.Println(OpenP2PVersion)
			return
		case "install":
			install()
			return
		case "uninstall":
			uninstall(true)
			return
		case "start":
			d := daemon{}
			err := d.Control("start", "", nil)
			if err != nil {
				log.Println("openp2p start error:", err)
				return
			}
			log.Println("openp2p start ok")
			return
		case "stop":
			d := daemon{}
			err := d.Control("stop", "", nil)
			if err != nil {
				log.Println("openp2p stop error:", err)
				return
			}
			log.Println("openp2p stop ok")
			return
		}
	} else {
		installByFilename()
	}
	parseParams("", "")
	gLog.i("openp2p start. version: %s", OpenP2PVersion)
	gLog.i("Contact: QQ group 16947733, Email openp2p.cn@gmail.com")

	if gConf.daemonMode {
		d := daemon{}
		d.run()
		return
	}

	gLog.i("node=%s, serverHost=%s, serverPort=%d", gConf.Network.Node, gConf.Network.ServerHost, gConf.Network.ServerPort)
	setFirewall()
	err := setRLimit()
	if err != nil {
		gLog.i("setRLimit error:%s", err)
	}
	P2PNetworkInstance()
	if ok := GNetwork.Connect(30000); !ok {
		gLog.e("P2PNetwork login error")
		return
	}
	// gLog.i("waiting for connection...")
	forever := make(chan bool)
	<-forever
}

// for Android app
// gomobile not support uint64 exported to java

func RunAsModule(baseDir string, token string, bw int, logLevel int) *P2PNetwork {
	return RunAsModuleWithNode(baseDir, token, "", bw, logLevel)
}

// RunAsModuleWithNode starts the mobile core with a platform-provided device
// name candidate. The candidate is used only when config.json does not exist,
// or when its network.Node field is absent or empty. An existing non-empty
// node name is never overwritten.
func RunAsModuleWithNode(baseDir string, token string, nodeCandidate string, bw int, logLevel int) *P2PNetwork {
	rand.Seed(time.Now().UnixNano())
	if err := os.Chdir(baseDir); err != nil {
		return nil
	}
	gLog = NewLogger(baseDir, ProductName, LvINFO, 1024*1024, LogFile|LogConsole)
	if gLog == nil {
		return nil
	}

	parseCommand := ""
	if shouldUseNodeCandidate("config.json") {
		if candidate := normalizeNodeCandidate(nodeCandidate); candidate != "" {
			parseCommand = "-node=" + candidate
		}
	}
	parseParams("", parseCommand)

	n, err := strconv.ParseUint(token, 10, 64)
	if err == nil && n > 0 {
		gConf.setToken(n)
	}
	if n <= 0 && gConf.Network.Token == 0 { // not input token
		gLog.e("OpenP2PStart rejected: token is missing or invalid")
		return nil
	}
	// gLog.setLevel(LogLevel(logLevel))
	gConf.setShareBandwidth(bw)
	gLog.i("openp2p start. version: %s", OpenP2PVersion)
	gLog.i("Contact: QQ group 16947733, Email openp2p.cn@gmail.com")
	gLog.i("node=%s, serverHost=%s, serverPort=%d", gConf.Network.Node, gConf.Network.ServerHost, gConf.Network.ServerPort)

	P2PNetworkInstance()
	if ok := GNetwork.Connect(30000); !ok {
		gLog.e("P2PNetwork login error")
		return nil
	}
	// gLog.i("waiting for connection...")
	return GNetwork
}

func shouldUseNodeCandidate(configPath string) bool {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return os.IsNotExist(err)
	}
	var persisted struct {
		Network struct {
			Node string
		} `json:"network"`
	}
	if err := json.Unmarshal(data, &persisted); err != nil {
		return false
	}
	return strings.TrimSpace(persisted.Network.Node) == ""
}

func normalizeNodeCandidate(candidate string) string {
	candidate = strings.TrimSpace(candidate)
	if candidate == "" {
		return ""
	}
	// parseParams uses strings.Split for module command arguments, so keep the
	// candidate a single argument while retaining a readable device name.
	candidate = strings.Join(strings.Fields(candidate), "-")
	runes := []rune(candidate)
	if len(runes) > 31 {
		runes = runes[:31]
		candidate = string(runes)
	}
	for len([]rune(candidate)) < MinNodeNameLen {
		candidate += "0"
	}
	return candidate
}

// StopModule stops the in-process core used by mobile clients. Desktop builds
// terminate the child process from the launcher, while Android keeps the core
// inside the app process and needs an explicit, non-process-exiting shutdown.
func StopModule() {
	networkMu.Lock()
	defer networkMu.Unlock()
	if GNetwork != nil {
		GNetwork.shutdown()
		if v4l != nil {
			v4l.stop()
			v4l = nil
		}
		GNetwork = nil
	}
}

// IsModuleRunning reports whether the in-process core instance is still
// alive. It deliberately does not require the control connection to be
// online and does not depend on SD-WAN/TUN state: transient reconnects and
// port-forward-only configurations are both valid running states.
func IsModuleRunning() bool {
	networkMu.Lock()
	defer networkMu.Unlock()
	if GNetwork == nil {
		return false
	}
	select {
	case <-GNetwork.shutdownCh:
		return false
	default:
		return true
	}
}

func RunCmd(cmd string) {
	rand.Seed(time.Now().UnixNano())
	baseDir := filepath.Dir(os.Args[0])
	os.Chdir(baseDir) // for system service
	gLog = NewLogger(baseDir, ProductName, LvINFO, 1024*1024, LogFile|LogConsole)

	parseParams("", cmd)
	setFirewall()
	err := setRLimit()
	if err != nil {
		gLog.i("setRLimit error:%s", err)
	}
	P2PNetworkInstance()
	if ok := GNetwork.Connect(30000); !ok {
		gLog.e("P2PNetwork login error")
		return
	}
	forever := make(chan bool)
	<-forever
}

func GetToken(baseDir string) string {
	os.Chdir(baseDir)
	gConf.load()
	return fmt.Sprintf("%d", gConf.Network.Token)
}

func SetToken(token string) {
	n, err := strconv.ParseUint(token, 10, 64)
	if err == nil && n > 0 {
		gConf.setToken(n)
		gConf.save()
	}
}

func Stop() {
	os.Exit(0)
}
