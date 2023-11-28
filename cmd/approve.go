package main

import (
	"encoding/json"
	"net/http"
)

func approveHandler(w http.ResponseWriter, r *http.Request, c ClientInterface, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		handleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

	_, res, err := c.ApproveMergeRequest(d.ProjectId, d.MergeId, nil, nil)

	if err != nil {
		handleError(w, err, "Could not approve merge request", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/approve"}, "Could not approve merge request", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: "Approved MR",
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
