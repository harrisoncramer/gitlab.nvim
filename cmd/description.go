package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type SummaryUpdateRequest struct {
	Description string `json:"description"`
	Title       string `json:"title"`
}

type SummaryUpdateResponse struct {
	SuccessResponse
	MergeRequest *gitlab.MergeRequest `json:"mr"`
}

func SummaryHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPut {
		w.Header().Set("Allow", http.MethodPut)
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var SummaryUpdateRequest SummaryUpdateRequest
	err = json.Unmarshal(body, &SummaryUpdateRequest)

	if err != nil {
		c.handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	mr, res, err := c.git.MergeRequests.UpdateMergeRequest(c.projectId, c.mergeId, &gitlab.UpdateMergeRequestOptions{
		Description: &SummaryUpdateRequest.Description,
		Title:       &SummaryUpdateRequest.Title,
	})

	if err != nil {
		c.handleError(w, err, "Could not edit merge request summary", http.StatusBadRequest)
		return
	}

	if res.StatusCode != http.StatusOK {
		c.handleError(w, err, "Could not edit merge request summary", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)

	response := SummaryUpdateResponse{
		SuccessResponse: SuccessResponse{
			Message: "Summary updated",
			Status:  http.StatusOK,
		},
		MergeRequest: mr,
	}

	json.NewEncoder(w).Encode(response)

}
