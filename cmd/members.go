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
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(*gitlab.Client)
	d := r.Context().Value("data").(*ProjectInfo)

	projectMemberOptions := gitlab.ListProjectMembersOptions{
		ListOptions: gitlab.ListOptions{
			PerPage: 100,
		},
	}

	projectMembers, res, err := c.ProjectMembers.ListAllProjectMembers(d.ProjectId, &projectMemberOptions)
	if err != nil {
		HandleError(w, err, "Could not fetch project users", res.StatusCode)
	}

	w.WriteHeader(http.StatusOK)

	response := ProjectMembersResponse{
		SuccessResponse: SuccessResponse{
			Status:  http.StatusOK,
			Message: "Project users fetched successfully",
		},
		ProjectMembers: projectMembers,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
