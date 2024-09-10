package app

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type AssigneeUpdateRequest struct {
	Ids []int `json:"ids"`
}

type AssigneeUpdateResponse struct {
	SuccessResponse
	Assignees []*gitlab.BasicUser `json:"assignees"`
}

type AssigneesRequestResponse struct {
	SuccessResponse
	Assignees []int `json:"assignees"`
}

type assigneesService struct {
	data
	client MergeRequestUpdater
}

/* assigneesHandler adds or removes assignees from a merge request. */
func (a assigneesService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
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
	var assigneeUpdateRequest AssigneeUpdateRequest
	err = json.Unmarshal(body, &assigneeUpdateRequest)

	if err != nil {
		handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	mr, res, err := a.client.UpdateMergeRequest(a.projectInfo.ProjectId, a.projectInfo.MergeId, &gitlab.UpdateMergeRequestOptions{
		AssigneeIDs: &assigneeUpdateRequest.Ids,
	})

	if err != nil {
		handleError(w, err, "Could not modify merge request assignees", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/assignee"}, "Could not modify merge request assignees", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := AssigneeUpdateResponse{
		SuccessResponse: SuccessResponse{
			Message: "Assignees updated",
			Status:  http.StatusOK,
		},
		Assignees: mr.Assignees,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
