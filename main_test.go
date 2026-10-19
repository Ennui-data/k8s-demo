package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealthEndpoints(t *testing.T) {
	for _, path := range []string{"/healthz", "/readyz"} {
		t.Run(path, func(t *testing.T) {
			rec := httptest.NewRecorder()
			newMux().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))

			if rec.Code != http.StatusOK {
				t.Fatalf("код ответа = %d, ожидался %d", rec.Code, http.StatusOK)
			}
			if body := rec.Body.String(); !strings.Contains(body, "ok") {
				t.Fatalf("тело ответа = %q, ожидалось наличие 'ok'", body)
			}
		})
	}
}

func TestInfoEndpoint(t *testing.T) {
	rec := httptest.NewRecorder()
	newMux().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/hello", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("код ответа = %d, ожидался %d", rec.Code, http.StatusOK)
	}

	var got info
	if err := json.NewDecoder(rec.Body).Decode(&got); err != nil {
		t.Fatalf("не удалось разобрать JSON: %v", err)
	}

	if got.Service != "k8s-demo" {
		t.Errorf("service = %q, ожидалось %q", got.Service, "k8s-demo")
	}
	if got.Path != "/hello" {
		t.Errorf("path = %q, ожидалось %q", got.Path, "/hello")
	}
	if got.Hostname == "" {
		t.Error("hostname пустой")
	}
	if got.GoVersion == "" {
		t.Error("go_version пустой")
	}
}
