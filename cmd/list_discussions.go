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
	Notes       []*gitlab.Note       `json:"note"`
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

func (c *Client) ListDiscussions() ([]*gitlab.Discussion, []*gitlab.Note, int, error) {

	mergeRequestDiscussionOptions := gitlab.ListMergeRequestDiscussionsOptions{
		Page:    1,
		PerPage: 250,
	}
	discussions, res, err := c.git.Discussions.ListMergeRequestDiscussions(c.projectId, c.mergeId, &mergeRequestDiscussionOptions, nil)

	if err != nil {
		return nil, nil, res.Response.StatusCode, fmt.Errorf("Listing discussions failed: %w", err)
	}

	var realDiscussions []*gitlab.Discussion
	for i := 0; i < len(discussions); i++ {
		notes := discussions[i].Notes
		for j := 0; j < len(notes); j++ {
			if notes[j].Type == gitlab.NoteTypeValue("DiffNote") {
				realDiscussions = append(realDiscussions, discussions[i])
				break
			}
		}
	}

	sortedDiscussions := SortableDiscussions(realDiscussions)
	sort.Sort(sortedDiscussions)

	mergeRequestNoteOptions := gitlab.ListMergeRequestNotesOptions{}

	notes, res, err := c.git.Notes.ListMergeRequestNotes(c.projectId, c.mergeId, &mergeRequestNoteOptions)

	if err != nil {
		return nil, nil, res.Response.StatusCode, fmt.Errorf("Listing notes failed: %w", err)
	}

	var filteredNotes []*gitlab.Note
	for i := 0; i < len(notes); i++ {
		if notes[i].Position == nil && notes[i].System == false {
			filteredNotes = append(filteredNotes, notes[i])
		}
	}

	return sortedDiscussions, filteredNotes, http.StatusOK, nil
}

func ListDiscussionsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	if r.Method != http.MethodGet {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	discussions, notes, status, err := c.ListDiscussions()

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
		Discussions: discussions,
		Notes:       notes,
	}

	json.NewEncoder(w).Encode(response)
}
