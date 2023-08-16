package main

import (
	"encoding/json"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type ProjectMembersResponse struct {
	SuccessResponse
	ProjectMembers []*gitlab.ProjectMember
}

func ProjectMembersHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")

	projectMemberOptions := gitlab.ListProjectMembersOptions{}
	projectMembers, res, err := c.git.ProjectMembers.ListAllProjectMembers(c.projectId, &projectMemberOptions)
	if err != nil {
		c.handleError(w, err, "Could not fetch project users", res.StatusCode)
	}

	w.WriteHeader(http.StatusOK)

	response := ProjectMembersResponse{
		SuccessResponse: SuccessResponse{
			Status:  http.StatusOK,
			Message: "Project users fetched successfully",
		},
		ProjectMembers: projectMembers,
	}

	json.NewEncoder(w).Encode(response)

	return
}
