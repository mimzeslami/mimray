// mimray-helper: a small root service so the app can start the VPN core without
// asking for a password on every connect.
//
// Security model:
//   - listens on a unix socket owned by one user (mode 0600) and also checks the
//     peer's uid on every connection;
//   - runs only its own root-owned sing-box binary;
//   - accepts only configs that pass validate() (no file access, loopback-only API);
//   - the core lives exactly as long as the client's connection: when the app
//     disconnects, quits or crashes, the core is stopped.
//
// Protocol (one JSON object per line):
//
//	client -> {"cmd":"version"}                 helper -> {"version":"3"}
//	client -> {"cmd":"start","config":{...}}    helper -> {"log":"..."}* then {"exit":N} | {"error":"..."}
//	client -> {"cmd":"stop"} or closes the connection: core is stopped
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

const version = "3"

var (
	mu      sync.Mutex
	running *exec.Cmd // at most one core at a time
)

func main() {
	sock := flag.String("sock", "", "unix socket path")
	uid := flag.Int("uid", -1, "the only (non-root) user allowed to connect")
	core := flag.String("core", "", "sing-box binary (root-owned)")
	dir := flag.String("dir", "", "root-owned working directory")
	check := flag.String("check", "", "validate a config file and exit")
	flag.Parse()

	if *check != "" {
		os.Exit(checkFile(*check))
	}
	if *sock == "" || *uid < 0 || *core == "" || *dir == "" {
		log.Fatal("usage: mimray-helper -sock PATH -uid N -core SING_BOX -dir WORKDIR")
	}
	if err := os.MkdirAll(*dir, 0o700); err != nil {
		log.Fatal(err)
	}

	_ = os.Remove(*sock)
	l, err := net.Listen("unix", *sock)
	if err != nil {
		log.Fatal(err)
	}
	if err := os.Chown(*sock, *uid, -1); err != nil {
		log.Fatal(err)
	}
	if err := os.Chmod(*sock, 0o600); err != nil {
		log.Fatal(err)
	}

	go func() { // stop the core when the service is stopped
		s := make(chan os.Signal, 1)
		signal.Notify(s, syscall.SIGTERM, syscall.SIGINT)
		<-s
		mu.Lock()
		if running != nil {
			terminate(running)
		}
		mu.Unlock()
		_ = os.Remove(*sock)
		os.Exit(0)
	}()

	log.Printf("mimray-helper %s listening on %s for uid %d", version, *sock, *uid)
	for {
		c, err := l.Accept()
		if err != nil {
			continue
		}
		go serve(c.(*net.UnixConn), *uid, *core, *dir)
	}
}

func serve(c *net.UnixConn, uid int, core, dir string) {
	defer c.Close()
	var wmu sync.Mutex
	enc := json.NewEncoder(c)
	send := func(v any) {
		wmu.Lock()
		defer wmu.Unlock()
		_ = enc.Encode(v)
	}

	if p, err := peerUID(c); err != nil || (p != uid && p != 0) {
		send(map[string]string{"error": "not allowed"})
		return
	}

	r := bufio.NewReaderSize(io.LimitReader(c, 8<<20), 64<<10)
	line, err := r.ReadBytes('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return
	}
	var req struct {
		Cmd    string         `json:"cmd"`
		Config map[string]any `json:"config"`
	}
	if json.Unmarshal(line, &req) != nil {
		send(map[string]string{"error": "bad request"})
		return
	}

	switch req.Cmd {
	case "version":
		send(map[string]string{"version": version})
		return
	case "start":
	default:
		send(map[string]string{"error": "unknown command"})
		return
	}

	if err := validate(req.Config); err != nil {
		send(map[string]string{"error": "config rejected: " + err.Error()})
		return
	}

	mu.Lock()
	if running != nil {
		mu.Unlock()
		send(map[string]string{"error": "already connected"})
		return
	}
	cfg := filepath.Join(dir, "config.json")
	b, _ := json.Marshal(req.Config)
	if err := os.WriteFile(cfg, b, 0o600); err != nil {
		mu.Unlock()
		send(map[string]string{"error": err.Error()})
		return
	}
	cmd := exec.Command(core, "run", "-c", cfg, "-D", dir)
	cmd.Dir = dir
	out, _ := cmd.StdoutPipe()
	cmd.Stderr = cmd.Stdout
	if err := cmd.Start(); err != nil {
		mu.Unlock()
		send(map[string]string{"error": err.Error()})
		return
	}
	running = cmd
	mu.Unlock()

	go func() { // stream core output to the app
		s := bufio.NewScanner(out)
		for s.Scan() {
			send(map[string]string{"log": s.Text()})
		}
	}()

	gone := make(chan struct{})
	go func() { // client said stop, or disconnected (quit/crash)
		for {
			l, err := r.ReadBytes('\n')
			var m struct{ Cmd string }
			if err != nil || (json.Unmarshal(l, &m) == nil && m.Cmd == "stop") {
				close(gone)
				return
			}
		}
	}()

	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err = <-done:
	case <-gone:
		terminate(cmd)
		err = <-done
	}
	mu.Lock()
	running = nil
	mu.Unlock()
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	}
	send(map[string]int{"exit": code})
}

// terminate stops the core gracefully (so it removes its routes), then forcefully.
func terminate(cmd *exec.Cmd) {
	if cmd.Process == nil {
		return
	}
	_ = cmd.Process.Signal(syscall.SIGTERM)
	go func() {
		time.Sleep(5 * time.Second)
		_ = cmd.Process.Kill()
	}()
}

func checkFile(path string) int {
	b, err := os.ReadFile(path)
	if err != nil {
		fmt.Println(err)
		return 1
	}
	var c map[string]any
	if err := json.Unmarshal(b, &c); err != nil {
		fmt.Println(err)
		return 1
	}
	if err := validate(c); err != nil {
		fmt.Println("rejected:", err)
		return 1
	}
	fmt.Println("ok")
	return 0
}
