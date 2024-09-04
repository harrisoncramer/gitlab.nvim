package app

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type DraftNotePublisher interface {
	PublishAllDraftNotes(pid interface{}, mergeRequest int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
	PublishDraftNote(pid interface{}, mergeRequest int, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
}

type draftNotePublisherService struct {
	data
	client DraftNotePublisher
}

func (a draftNotePublisherService) handler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		handleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var draftNotePublishRequest DraftNotePublishRequest
	err = json.Unmarshal(body, &draftNotePublishRequest)

	if err != nil {
		handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	var res *gitlab.Response
	if draftNotePublishRequest.PublishAll {
		res, err = a.client.PublishAllDraftNotes(a.projectInfo.ProjectId, a.projectInfo.MergeId)
	} else {
		if draftNotePublishRequest.Note == 0 {
			handleError(w, errors.New("No ID provided"), "Must provide Note ID", http.StatusBadRequest)
			return
		}
		res, err = a.client.PublishDraftNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, draftNotePublishRequest.Note)
	}

	if err != nil {
		handleError(w, err, "Could not publish draft note(s)", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/draft_notes/publish"}, "Could not publish dfaft note", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: "Draft note(s) published",
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
