package main

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

func RevokeHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(*gitlab.Client)
	d := r.Context().Value("data").(*ProjectInfo)

	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		HandleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	res, err := c.MergeRequestApprovals.UnapproveMergeRequest(d.ProjectId, d.MergeId, nil, nil)

	if err != nil {
		HandleError(w, err, "Could not revoke approval", http.StatusBadRequest)
		return
	}

	/* TODO: Check for non-200 status codes */
	w.WriteHeader(res.StatusCode)
	response := SuccessResponse{
		Message: "Success! Revoked MR approval.",
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
