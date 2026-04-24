package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"runtime"
	"time"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	buildID := os.Getenv("BUILD_ID")
	if buildID == "" {
		buildID = "dev"
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"status": "ok",
			"time":   time.Now().Unix(),
		})
	})

	mux.HandleFunc("/buildinfo", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"build_id":   buildID,
			"go_version": runtime.Version(),
			"service":    "ttpos-accept-server",
		})
	})

	mux.HandleFunc("/api/menu", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"items": []map[string]any{
				{"id": 1, "name": "Pad Thai", "price": 120},
				{"id": 2, "name": "Green Curry", "price": 150},
			},
		})
	})

	fmt.Printf("ttpos-accept-server starting on :%s (build_id=%s)\n", port, buildID)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		fmt.Fprintf(os.Stderr, "server error: %v\n", err)
		os.Exit(1)
	}
}
