package app

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
)

type killer struct{}

func (k killer) Signal() {}
func (k killer) String() string {
	return "0"
}

type ShutdownHandler interface {
	WatchForShutdown(server *http.Server)
	ServeHTTP(w http.ResponseWriter, r *http.Request)
}

type shutdownService struct {
	sigCh chan os.Signal
}

func (s shutdownService) WatchForShutdown(server *http.Server) {
	/* Handles shutdown requests */
	<-s.sigCh
	err := server.Shutdown(context.Background())
	if err != nil {
		fmt.Fprintf(os.Stderr, "Server could not shut down gracefully: %s\n", err)
		os.Exit(1)
	}
}

type ShutdownRequest struct {
	Restart bool `json:"restart"`
}

/* Shuts down the HTTP server and exit the process by signaling to the shutdown channel */
func (s shutdownService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	payload := r.Context().Value(payload("payload")).(*ShutdownRequest)

	var text = "Shut down server"
	if payload.Restart {
		text = "Restarted server"
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{Message: text}

	err := json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	} else {
		s.sigCh <- killer{}
	}
}
