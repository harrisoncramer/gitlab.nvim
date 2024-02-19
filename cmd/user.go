package main

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type UserResponse struct {
	SuccessResponse
	User *gitlab.User `json:"user"`
}

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

	if res.StatusCode >= 300 {
		handleError(w, err, "User API returned non-200 status", res.StatusCode)
		return
	}

	response := UserResponse{
		SuccessResponse: SuccessResponse{
			Message: "User fetched successfully",
			Status:  http.StatusOK,
		},
		User: user,
	}

	json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
