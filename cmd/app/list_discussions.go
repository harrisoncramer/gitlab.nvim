package app

import (
	"io"
	"net/http"
	"sort"
	"sync"

	"encoding/json"

	"github.com/xanzy/go-gitlab"
)

func Contains[T comparable](elems []T, v T) bool {
	for _, s := range elems {
		if v == s {
			return true
		}
	}
	return false
}

type DiscussionsRequest struct {
	Blacklist []string `json:"blacklist"`
}

type DiscussionsResponse struct {
	SuccessResponse
	Discussions         []*gitlab.Discussion         `json:"discussions"`
	UnlinkedDiscussions []*gitlab.Discussion         `json:"unlinked_discussions"`
	Emojis              map[int][]*gitlab.AwardEmoji `json:"emojis"`
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

type DiscussionsLister interface {
	ListMergeRequestDiscussions(pid interface{}, mergeRequest int, opt *gitlab.ListMergeRequestDiscussionsOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.Discussion, *gitlab.Response, error)
	ListMergeRequestAwardEmojiOnNote(pid interface{}, mergeRequestIID int, noteID int, opt *gitlab.ListAwardEmojiOptions, options ...gitlab.RequestOptionFunc) ([]*gitlab.AwardEmoji, *gitlab.Response, error)
}

type discussionsListerService struct {
	data
	client DiscussionsLister
}

/*
listDiscussionsHandler lists all discusions for a given merge request, both those linked and unlinked to particular points in the code.
The responses are sorted by date created, and blacklisted users are not included
*/
func (a discussionsListerService) handler(w http.ResponseWriter, r *http.Request) {
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

	mergeRequestDiscussionOptions := gitlab.ListMergeRequestDiscussionsOptions{
		Page:    1,
		PerPage: 250,
	}

	discussions, res, err := a.client.ListMergeRequestDiscussions(a.projectInfo.ProjectId, a.projectInfo.MergeId, &mergeRequestDiscussionOptions)

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
	var unlinkedDiscussions []*gitlab.Discussion
	var linkedDiscussions []*gitlab.Discussion

	for _, discussion := range discussions {
		if discussion.Notes == nil || len(discussion.Notes) == 0 || Contains(requestBody.Blacklist, discussion.Notes[0].Author.Username) {
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

	/* Collect IDs in order to fetch emojis */
	var noteIds []int
	for _, discussion := range discussions {
		for _, note := range discussion.Notes {
			noteIds = append(noteIds, note.ID)
		}
	}

	emojis, err := a.fetchEmojisForNotesAndComments(noteIds)
	if err != nil {
		handleError(w, err, "Could not fetch emojis", http.StatusInternalServerError)
		return
	}

	sortedLinkedDiscussions := SortableDiscussions(linkedDiscussions)
	sortedUnlinkedDiscussions := SortableDiscussions(unlinkedDiscussions)

	sort.Sort(sortedLinkedDiscussions)
	sort.Sort(sortedUnlinkedDiscussions)

	w.WriteHeader(http.StatusOK)
	response := DiscussionsResponse{
		SuccessResponse: SuccessResponse{
			Message: "Discussions retrieved",
			Status:  http.StatusOK,
		},
		Discussions:         linkedDiscussions,
		UnlinkedDiscussions: unlinkedDiscussions,
		Emojis:              emojis,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

/*
Fetches emojis for a set of notes and comments in parallel and returns a map of note IDs to their emojis.
Gitlab's API does not allow for fetching notes for an entire discussion thread so we have to do it per-note.
*/
func (a discussionsListerService) fetchEmojisForNotesAndComments(noteIDs []int) (map[int][]*gitlab.AwardEmoji, error) {
	var wg sync.WaitGroup

	emojis := make(map[int][]*gitlab.AwardEmoji)
	mu := &sync.Mutex{}
	errs := make(chan error, len(noteIDs))
	emojiChan := make(chan struct {
		noteID int
		emojis []*gitlab.AwardEmoji
	}, len(noteIDs))

	for _, noteID := range noteIDs {
		wg.Add(1)
		go func(noteID int) {
			defer wg.Done()
			emojis, _, err := a.client.ListMergeRequestAwardEmojiOnNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, noteID, &gitlab.ListAwardEmojiOptions{})
			if err != nil {
				errs <- err
				return
			}
			emojiChan <- struct {
				noteID int
				emojis []*gitlab.AwardEmoji
			}{noteID, emojis}
		}(noteID)
	}

	/* Close the channels when all goroutines finish */
	go func() {
		wg.Wait()
		close(errs)
		close(emojiChan)
	}()

	/* Collect emojis */
	for e := range emojiChan {
		mu.Lock()
		emojis[e.noteID] = e.emojis
		mu.Unlock()
	}

	/* Check if any errors occurred */
	if len(errs) > 0 {
		for err := range errs {
			if err != nil {
				return nil, err
			}
		}
	}

	return emojis, nil
}
