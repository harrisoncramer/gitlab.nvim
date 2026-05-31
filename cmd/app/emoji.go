package app

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"

	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type CreateNoteEmojiPost struct {
	Emoji  string `json:"emoji"`
	NoteId int64  `json:"note_id"`
}

type CreateEmojiResponse struct {
	SuccessResponse
	Emoji *gitlab.AwardEmoji
}

type EmojiManager interface {
	DeleteMergeRequestAwardEmojiOnNote(pid interface{}, mergeRequestIID int64, noteID int64, awardID int64, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error)
	CreateMergeRequestAwardEmojiOnNote(pid interface{}, mergeRequestIID int64, noteID int64, opt *gitlab.CreateAwardEmojiOptions, options ...gitlab.RequestOptionFunc) (*gitlab.AwardEmoji, *gitlab.Response, error)
}

type emojiService struct {
	data
	client EmojiManager
}

func (a emojiService) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodPost:
		a.postEmojiOnNote(w, r)
	case http.MethodDelete:
		a.deleteEmojiFromNote(w, r)
	}
}

/* deleteEmojiFromNote deletes an emoji from a note based on the emoji (awardable) ID and the note's ID */
func (a emojiService) deleteEmojiFromNote(w http.ResponseWriter, r *http.Request) {

	suffix := strings.TrimPrefix(r.URL.Path, "/mr/awardable/note/")
	ids := strings.Split(suffix, "/")

	if len(ids) < 2 {
		handleError(w, errors.New("missing IDs"), "Must provide note ID and awardable ID", http.StatusBadRequest)
		return
	}

	noteId, err := strconv.ParseInt(ids[0], 10, 64)
	if err != nil {
		handleError(w, err, "Could not convert note ID to integer", http.StatusBadRequest)
		return
	}

	awardableId, err := strconv.ParseInt(ids[1], 10, 64)
	if err != nil {
		handleError(w, err, "Could not convert awardable ID to integer", http.StatusBadRequest)
		return
	}

	res, err := a.client.DeleteMergeRequestAwardEmojiOnNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, noteId, awardableId)

	if err != nil {
		handleError(w, err, "Could not delete awardable", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not delete awardable", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{Message: "Emoji deleted"}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

/* postEmojiOnNote adds an emojis to a note based on the note's ID */
func (a emojiService) postEmojiOnNote(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var emojiPost CreateNoteEmojiPost
	err = json.Unmarshal(body, &emojiPost)

	if err != nil {
		handleError(w, err, "Could not unmarshal request body", http.StatusBadRequest)
		return
	}

	awardEmoji, res, err := a.client.CreateMergeRequestAwardEmojiOnNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, emojiPost.NoteId, &gitlab.CreateAwardEmojiOptions{
		Name: emojiPost.Emoji,
	})

	if err != nil {
		handleError(w, err, "Could not post emoji", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{r.URL.Path}, "Could not post emoji", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := CreateEmojiResponse{
		SuccessResponse: SuccessResponse{Message: "Merge requests retrieved"},
		Emoji:           awardEmoji,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
