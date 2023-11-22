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
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(*gitlab.Client)
	d := r.Context().Value("data").(*ProjectInfo)

	if r.Method != http.MethodPut {
		w.Header().Set("Allow", http.MethodPut)
		HandleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		HandleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var SummaryUpdateRequest SummaryUpdateRequest
	err = json.Unmarshal(body, &SummaryUpdateRequest)

	if err != nil {
		HandleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	mr, res, err := c.MergeRequests.UpdateMergeRequest(d.ProjectId, d.MergeId, &gitlab.UpdateMergeRequestOptions{
		Description: &SummaryUpdateRequest.Description,
		Title:       &SummaryUpdateRequest.Title,
	})

	if err != nil {
		HandleError(w, err, "Could not edit merge request summary", http.StatusBadRequest)
		return
	}

	if res.StatusCode != http.StatusOK {
		HandleError(w, err, "Could not edit merge request summary", http.StatusBadRequest)
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

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}

}
