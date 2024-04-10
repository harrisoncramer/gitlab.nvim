package main

import (
	"fmt"
	"net/http"
)

/* commentHandler creates, edits, and deletes draft discussions (comments, multi-line comments) */
func (a *api) draftCommentHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodPost:
		a.postDraftComment(w, r)
	case http.MethodPatch:
		a.editDraftComment(w, r)
	case http.MethodDelete:
		a.deleteDraftComment(w, r)
	default:
		w.Header().Set("Access-Control-Allow-Methods", fmt.Sprintf("%s, %s, %s", http.MethodDelete, http.MethodPost, http.MethodPatch))
		handleError(w, InvalidRequestError{}, "Expected DELETE, POST or PATCH", http.StatusMethodNotAllowed)
	}
}

/* postComment creates a draft comment */
func (a *api) postDraftComment(w http.ResponseWriter, r *http.Request) {}

/* deleteComment deletes a draft comment */
func (a *api) deleteDraftComment(w http.ResponseWriter, r *http.Request) {}

/* deleteComment edits a draft comment */
func (a *api) editDraftComment(w http.ResponseWriter, r *http.Request) {}
