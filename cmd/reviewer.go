package main

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type ReviewerUpdateRequest struct {
	Ids []int `json:"ids"`
}

type ReviewerUpdateResponse struct {
	SuccessResponse
	Reviewers []*gitlab.BasicUser `json:"reviewers"`
}

type ReviewersRequestResponse struct {
	SuccessResponse
	Reviewers []int `json:"reviewers"`
}

func ReviewersHandler(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPut {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPut)
		HandleError(w, InvalidRequestError{}, "Expected PUT", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		HandleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var reviewerUpdateRequest ReviewerUpdateRequest
	err = json.Unmarshal(body, &reviewerUpdateRequest)

	if err != nil {
		HandleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	mr, res, err := c.UpdateMergeRequest(d.ProjectId, d.MergeId, &gitlab.UpdateMergeRequestOptions{
		ReviewerIDs: &reviewerUpdateRequest.Ids,
	})

	if err != nil {
		HandleError(w, err, "Could not modify merge request reviewers", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		HandleError(w, GenericError{endpoint: "/mr/reviewer"}, "Gitlab returned non-200 status", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := ReviewerUpdateResponse{
		SuccessResponse: SuccessResponse{
			Message: "Reviewers updated",
			Status:  http.StatusOK,
		},
		Reviewers: mr.Reviewers,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
