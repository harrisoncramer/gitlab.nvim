package main

import (
	"fmt"
	"net/http"
)

func (a *api) meHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodGet {
		w.Header().Set("Access-Control-Allow-Methods", fmt.Sprintf("%s", http.MethodGet))
		handleError(w, InvalidRequestError{}, "Expected GET", http.StatusMethodNotAllowed)
		return
	}

	user, res, err := a.client.CurrentUser()

	if err != nil {
		handleError(w, err, "Failed to get current user", http.StatusInternalServerError)
		return
	}

  if res.StatusCode >= 300 

}
