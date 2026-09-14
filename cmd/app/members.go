package app

import (
	"encoding/json"
	"net/http"
	"slices"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type ProjectMembersResponse struct {
	SuccessResponse
	ProjectMembers []*gitlab.ProjectMember
}

type ProjectMemberLister interface {
	ListAllProjectMembers(pid interface{}, opt *gitlab.ListProjectMembersOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error)
}

type projectMemberService struct {
	data
	client ProjectMemberLister
}

/* projectMembersHandler returns all members of the current Gitlab project */
func (a projectMemberService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	projectMemberOptions := gitlab.ListProjectMembersOptions{
		ListOptions: gitlab.ListOptions{
			PerPage: 100,
		},
	}

	it, hasErr := gitlab.Scan(func(p gitlab.PaginationOptionFunc) ([]*gitlab.ProjectMember, *gitlab.Response, error) {
		return a.client.ListAllProjectMembers(a.projectInfo.ProjectId, &projectMemberOptions, p)
	})
	projectMembers := slices.Collect(it)

	if err := hasErr(); err != nil {
		handleError(w, err, "Could not retrieve project members", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)

	response := ProjectMembersResponse{
		SuccessResponse: SuccessResponse{Message: "Project members retrieved"},
		ProjectMembers:  projectMembers,
	}

	err := json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
