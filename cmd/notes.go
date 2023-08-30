package main

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type PostNoteRequest struct {
	Note string `json:"note"`
}

func DeleteNote(w http.ResponseWriter, r *http.Request) {
}

func PostNote(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	var postNoteRequest PostNoteRequest
	json.Unmarshal(body, &postNoteRequest)

	opts := gitlab.CreateMergeRequestNoteOptions{
		Body: gitlab.String(postNoteRequest.Note),
	}

	_, res, err := c.git.Notes.CreateMergeRequestNote(c.projectId, c.mergeId, &opts)
	if err != nil {
		c.handleError(w, err, "Could not create note", res.StatusCode)
		return
	}

	/* TODO: Check status code */
	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: "Note created succesfully",
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)

}

func EditNote(w http.ResponseWriter, r *http.Request) {
}

func NoteHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodDelete:
		DeleteNote(w, r)
	case http.MethodPost:
		PostNote(w, r)
	case http.MethodPatch:
		EditNote(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}
