package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
)

type killer struct{}

func (k killer) Signal() {}
func (k killer) String() string {
	return "0"
}

type ShutdownRequest struct {
	Restart bool `json:"restart"`
}

func (a *api) shutdownHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

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

	var text = "Shut down Go server!"
	if shutdownRequest.Restart {
		text = "Restarted Go server!"
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: text,
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	} else {
		a.sigCh <- killer{}
	}
}
