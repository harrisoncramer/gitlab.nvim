package main

import (
	"errors"
	"fmt"
	"net/http"
	"sort"

	"encoding/json"

	"github.com/xanzy/go-gitlab"
)

type SortableDiscussions []*gitlab.Discussion

type DiscussionsResponse struct {
	SuccessResponse
	Discussions []*gitlab.Discussion `json:"discussions"`
}

func (n SortableDiscussions) Len() int {
	return len(n)
}

func (d SortableDiscussions) Less(i int, j int) bool {
	iTime := d[i].Notes[len(d[i].Notes)-1].CreatedAt
	jTime := d[j].Notes[len(d[j].Notes)-1].CreatedAt
	return iTime.After(*jTime)

}

func (n SortableDiscussions) Swap(i, j int) {
	n[i], n[j] = n[j], n[i]
}

func (c *Client) ListDiscussions() ([]*gitlab.Discussion, int, error) {

	mergeRequestDiscussionOptions := gitlab.ListMergeRequestDiscussionsOptions{
		Page:    1,
		PerPage: 250,
	}
	discussions, res, err := c.git.Discussions.ListMergeRequestDiscussions(c.projectId, c.mergeId, &mergeRequestDiscussionOptions, nil)

	if err != nil {
		return nil, res.Response.StatusCode, fmt.Errorf("Listing discussions failed: %w", err)
	}

	var diffNotes []*gitlab.Discussion
	for i := 0; i < len(discussions); i++ {
		notes := discussions[i].Notes
		for j := 0; j < len(notes); j++ {
			if !notes[j].System {
				diffNotes = append(diffNotes, discussions[i])
				break
			}
		}
	}

	sortedDiscussions := SortableDiscussions(diffNotes)
	sort.Sort(sortedDiscussions)

	return sortedDiscussions, http.StatusOK, nil
}

func ListDiscussionsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	if r.Method != http.MethodGet {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	msg, status, err := c.ListDiscussions()

	if err != nil {
		c.handleError(w, err, "Could not list discussions", http.StatusBadRequest)
		return
	}

	/* TODO: Check for non-200 statuses */
	w.WriteHeader(status)
	response := DiscussionsResponse{
		SuccessResponse: SuccessResponse{
			Message: "Discussions successfully fetched.",
			Status:  http.StatusOK,
		},
		Discussions: msg,
	}

	json.NewEncoder(w).Encode(response)
}
