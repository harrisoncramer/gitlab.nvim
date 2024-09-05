package app

import (
	"encoding/json"
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

type summaryService struct {
	data
	client MergeRequestUpdater
}

func (a summaryService) handler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodPut {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPut)
		handleError(w, InvalidRequestError{}, "Expected PUT", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var SummaryUpdateRequest SummaryUpdateRequest
	err = json.Unmarshal(body, &SummaryUpdateRequest)

	if err != nil {
		handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	mr, res, err := a.client.UpdateMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &gitlab.UpdateMergeRequestOptions{
		Description: &SummaryUpdateRequest.Description,
		Title:       &SummaryUpdateRequest.Title,
	})

	if err != nil {
		handleError(w, err, "Could not edit merge request summary", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/summary"}, "Could not edit merge request summary", res.StatusCode)
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
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}

}
