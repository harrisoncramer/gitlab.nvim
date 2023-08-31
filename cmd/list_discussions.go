package main

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"sort"

	"encoding/json"

	"github.com/xanzy/go-gitlab"
)

type DiscussionsRequest struct {
	Blacklist []string `json:"blacklist"`
}

type DiscussionsResponse struct {
	SuccessResponse
	Discussions         []*gitlab.Discussion `json:"discussions"`
	UnlinkedDiscussions []*gitlab.Discussion `json:"unlinked_discussions"`
}

type SortableDiscussions []*gitlab.Discussion

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

func (c *Client) ListDiscussions(blacklist []string) ([]*gitlab.Discussion, []*gitlab.Discussion, int, error) {

	mergeRequestDiscussionOptions := gitlab.ListMergeRequestDiscussionsOptions{
		Page:    1,
		PerPage: 250,
	}
	discussions, res, err := c.git.Discussions.ListMergeRequestDiscussions(c.projectId, c.mergeId, &mergeRequestDiscussionOptions, nil)

	if err != nil {
		return nil, nil, res.Response.StatusCode, fmt.Errorf("Listing discussions failed: %w", err)
	}

	/* Filter out any discussions started by a blacklisted user
	and system discussions, then return them sorted by created date */
	var unlinkedDiscussions []*gitlab.Discussion
	var linkedDiscussions []*gitlab.Discussion
	for _, discussion := range discussions {
		if Contains(blacklist, discussion.Notes[0].Author.Username) > -1 {
			continue
		}
		for _, note := range discussion.Notes {
			if note.Type == gitlab.NoteTypeValue("DiffNote") {
				linkedDiscussions = append(linkedDiscussions, discussion)
				break
			} else if note.System == false && note.Position == nil {
				unlinkedDiscussions = append(unlinkedDiscussions, discussion)
				break
			}
		}
	}

	sortedLinkedDiscussions := SortableDiscussions(linkedDiscussions)
	sortedUnlinkedDiscussions := SortableDiscussions(unlinkedDiscussions)

	sort.Sort(sortedLinkedDiscussions)
	sort.Sort(sortedUnlinkedDiscussions)

	return sortedLinkedDiscussions, sortedUnlinkedDiscussions, http.StatusOK, nil
}

func ListDiscussionsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	if r.Method != http.MethodPost {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)

	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
	}

	var requestBody DiscussionsRequest
	err = json.Unmarshal(body, &requestBody)
	if err != nil {
		c.handleError(w, err, "Could not unmarshal request body", http.StatusBadRequest)
	}

	linkedDiscussions, unlinkedDiscussions, status, err := c.ListDiscussions(requestBody.Blacklist)

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
		Discussions:         linkedDiscussions,
		UnlinkedDiscussions: unlinkedDiscussions,
	}

	json.NewEncoder(w).Encode(response)
}
