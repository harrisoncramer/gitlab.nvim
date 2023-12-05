package main

import (
	"encoding/json"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type InfoResponse struct {
	SuccessResponse
	Info *gitlab.MergeRequest `json:"info"`
}

/* infoHandler fetches infomation about the current git project. The data returned here is used in many other API calls */
func (a *api) infoHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodGet {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodGet)
		handleError(w, InvalidRequestError{}, "Expected GET", http.StatusMethodNotAllowed)
		return
	}

	mr, res, err := a.client.GetMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &gitlab.GetMergeRequestsOptions{})
	if err != nil {
		handleError(w, err, "Could not get project info", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/info"}, "Could not get project info", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := InfoResponse{
		SuccessResponse: SuccessResponse{
			Message: "Merge requests retrieved",
			Status:  http.StatusOK,
		},
		Info: mr,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
