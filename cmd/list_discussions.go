package main

import (
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

/*
listDiscussionsHandler lists all discusions for a given merge request, both those linked and unlinked to particular points in the code.
The responses are sorted by date created, and blacklisted users are not included
*/
func (a *api) listDiscussionsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		handleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)

	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
	}

	defer r.Body.Close()

	var requestBody DiscussionsRequest
	err = json.Unmarshal(body, &requestBody)
	if err != nil {
		handleError(w, err, "Could not unmarshal request body", http.StatusBadRequest)
	}

	var unlinkedDiscussions []*gitlab.Discussion
	var linkedDiscussions []*gitlab.Discussion

	/* Repeat requests for multiple pages, as the maximum number of
	   items per page is 100 which may not be enough in bigger MRs. */
	/* TODO: Replace the hardcoded limit by the correct number that can
	   be obtained from the total number of items (X-Total). */
	for i := 1; i <= 3; i++ {
		mergeRequestDiscussionOptions := gitlab.ListMergeRequestDiscussionsOptions{
			Page:    i,
			PerPage: 100,
		}

		discussions, res, err := a.client.ListMergeRequestDiscussions(a.projectInfo.ProjectId, a.projectInfo.MergeId, &mergeRequestDiscussionOptions, nil)

		if err != nil {
			handleError(w, err, "Could not list discussions", http.StatusInternalServerError)
			return
		}

		if res.StatusCode >= 300 {
			handleError(w, GenericError{endpoint: "/mr/discussions/list"}, "Could not list discussions", res.StatusCode)
			return
		}

		/* Filter out any discussions started by a blacklisted user
		   and system discussions, then return them sorted by created date */
		for _, discussion := range discussions {
			if discussion.Notes == nil || len(discussion.Notes) == 0 || Contains(requestBody.Blacklist, discussion.Notes[0].Author.Username) > -1 {
				continue
			}
			for _, note := range discussion.Notes {
				if note.Type == gitlab.NoteTypeValue("DiffNote") {
					linkedDiscussions = append(linkedDiscussions, discussion)
					break
				} else if !note.System && note.Position == nil {
					unlinkedDiscussions = append(unlinkedDiscussions, discussion)
					break
				}
			}
		}

	}
	sortedLinkedDiscussions := SortableDiscussions(linkedDiscussions)
	sortedUnlinkedDiscussions := SortableDiscussions(unlinkedDiscussions)

	sort.Sort(sortedLinkedDiscussions)
	sort.Sort(sortedUnlinkedDiscussions)

	if err != nil {
		handleError(w, err, "Could not list discussions", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := DiscussionsResponse{
		SuccessResponse: SuccessResponse{
			Message: "Discussions retrieved",
			Status:  http.StatusOK,
		},
		Discussions:         linkedDiscussions,
		UnlinkedDiscussions: unlinkedDiscussions,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
