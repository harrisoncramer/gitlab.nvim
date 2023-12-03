package main

import (
	"errors"
	"net/http"
)

type killer struct{}

func (k killer) Signal() {}
func (k killer) String() string {
	return "0"
}

func (a *api) shutdownHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		w.Header().Set("Allow", http.MethodDelete)
		handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("Shutting down server..."))
	a.sigCh <- killer{}
}
