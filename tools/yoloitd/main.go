package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"yoloitd/handler"
	"yoloitd/server"
)

const protocolVersion = 1

func main() {
	var home string
	flag.StringVar(&home, "home", defaultHome(), "Runtime home directory")
	flag.Parse()

	if err := os.MkdirAll(home, 0o755); err != nil {
		log.Fatalf("Failed to create home directory: %v", err)
	}

	portPath := filepath.Join(home, "runtime.port")
	pidPath := filepath.Join(home, "runtime.pid")

	srv := server.New()
	h := handler.New(srv)

	httpSrv := &http.Server{
		Addr:    "127.0.0.1:0",
		Handler: h,
	}

	listener, err := net.Listen("tcp", httpSrv.Addr)
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	port := listener.Addr().(*net.TCPAddr).Port
	if err := os.WriteFile(portPath, []byte(fmt.Sprintf("%d", port)), 0o644); err != nil {
		log.Fatalf("Failed to write port file: %v", err)
	}
	if err := os.WriteFile(pidPath, []byte(fmt.Sprintf("%d", os.Getpid())), 0o644); err != nil {
		log.Fatalf("Failed to write pid file: %v", err)
	}

	defer func() {
		_ = os.Remove(portPath)
		_ = os.Remove(pidPath)
		srv.KillAll()
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		<-sigCh
		log.Println("Shutting down...")
		_ = httpSrv.Close()
	}()

	log.Printf("yoloitd listening on %s (home=%s)", listener.Addr(), home)

	if err := httpSrv.Serve(listener); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
}

func defaultHome() string {
	if os.Getenv("YOLOIT_DEV_RUNTIME") == "1" {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, ".config", "yoloit-dev", "runtime")
	}
	if h := os.Getenv("YOLOIT_RUNTIME_HOME"); h != "" {
		return h
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "yoloit", "runtime")
}
