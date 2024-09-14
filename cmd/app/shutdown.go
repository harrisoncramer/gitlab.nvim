package app

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
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
	} else {
		os.Exit(0)
	}
}

type ShutdownRequest struct {
	Restart bool `json:"restart"`
}

/* Shuts down the HTTP server and exit the process by signaling to the shutdown channel */
func (s shutdownService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	var shutdownRequest ShutdownRequest
	err = json.Unmarshal(body, &shutdownRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
		return
	}

	var text = "Shut down server"
	if shutdownRequest.Restart {
		text = "Restarted server"
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{Message: text}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	} else {
		s.sigCh <- killer{}
	}
}
