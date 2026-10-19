// Простейший HTTP-сервис для демонстрации CI/CD: отдаёт JSON с версией сборки
// и имеет эндпоинты для liveness/readiness проб Kubernetes.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"runtime"
	"time"
)

// version подставляется при сборке: -ldflags "-X main.version=..."
var version = "dev"

type info struct {
	Service   string `json:"service"`
	Version   string `json:"version"`
	Hostname  string `json:"hostname"`
	Path      string `json:"path"`
	GoVersion string `json:"go_version"`
}

func newMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/", handleInfo)
	mux.HandleFunc("/healthz", handleHealth) // liveness: процесс жив
	mux.HandleFunc("/readyz", handleHealth)  // readiness: готов принимать трафик
	return mux
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok\n"))
}

func handleInfo(w http.ResponseWriter, r *http.Request) {
	host, _ := os.Hostname()

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(info{
		Service:   "k8s-demo",
		Version:   version,
		Hostname:  host,
		Path:      r.URL.Path,
		GoVersion: runtime.Version(),
	})
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           newMux(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("k8s-demo %s слушает на %s", version, srv.Addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("ошибка сервера: %v", err)
	}
}
