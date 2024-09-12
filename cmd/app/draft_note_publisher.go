package app

import (
	"encoding/json"
	"errors"
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

type DraftNotePublishRequest struct {
	Note       int  `json:"note,omitempty"`
	PublishAll bool `json:"publish_all"`
}

func (a draftNotePublisherService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	payload := r.Context().Value("payload").(*DraftNotePublishRequest)

	var res *gitlab.Response
	var err error
	if payload.PublishAll {
		res, err = a.client.PublishAllDraftNotes(a.projectInfo.ProjectId, a.projectInfo.MergeId)
	} else {
		if payload.Note == 0 {
			handleError(w, errors.New("No ID provided"), "Must provide Note ID", http.StatusBadRequest)
			return
		}
		res, err = a.client.PublishDraftNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, payload.Note)
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
	response := SuccessResponse{Message: "Draft note(s) published"}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
