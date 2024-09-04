package app

import (
	"encoding/json"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type ProjectMembersResponse struct {
	SuccessResponse
	ProjectMembers []*gitlab.ProjectMember
}

type ProjectMemberLister interface {
	ListAllProjectMembers(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error)
}

type projectListerService struct {
	client      ProjectMemberLister
	projectInfo *ProjectInfo
}

/* projectMembersHandler returns all members of the current Gitlab project */
func (a projectListerService) handler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodGet {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodGet)
		handleError(w, InvalidRequestError{}, "Expected GET", http.StatusMethodNotAllowed)
		return
	}

	projectMemberOptions := gitlab.ListProjectMembersOptions{
		ListOptions: gitlab.ListOptions{
			PerPage: 100,
		},
	}

	projectMembers, res, err := a.client.ListAllProjectMembers(a.projectInfo.ProjectId, &projectMemberOptions)

	if err != nil {
		handleError(w, err, "Could not retrieve project members", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/project/members"}, "Could not retrieve project members", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)

	response := ProjectMembersResponse{
		SuccessResponse: SuccessResponse{
			Status:  http.StatusOK,
			Message: "Project members retrieved",
		},
		ProjectMembers: projectMembers,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
