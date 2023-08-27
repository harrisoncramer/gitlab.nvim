package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

const mrVersionsUrl = "%s/api/v4/projects/%s/merge_requests/%d/versions"

type PostCommentRequest struct {
	Comment        string `json:"comment"`
	FileName       string `json:"file_name"`
	NewLine        int    `json:"new_line"`
	OldLine        int    `json:"old_line"`
	HeadCommitSHA  string `json:"head_commit_sha"`
	BaseCommitSHA  string `json:"base_commit_sha"`
	StartCommitSHA string `json:"start_commit_sha"`
	Type           string `json:"type"`
}

type DeleteCommentRequest struct {
	NoteId       int    `json:"note_id"`
	DiscussionId string `json:"discussion_id"`
}

type EditCommentRequest struct {
	Comment      string `json:"comment"`
	NoteId       int    `json:"note_id"`
	DiscussionId string `json:"discussion_id"`
	Resolved     bool   `json:"resolved"`
}

type CommentResponse struct {
	SuccessResponse
	Comment *gitlab.Note `json:"note"`
}

func CommentHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodDelete:
		DeleteComment(w, r)
	case http.MethodPost:
		PostComment(w, r)
	case http.MethodPatch:
		EditComment(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func DeleteComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var deleteCommentRequest DeleteCommentRequest
	err = json.Unmarshal(body, &deleteCommentRequest)
	if err != nil {
		c.handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	res, err := c.git.Discussions.DeleteMergeRequestDiscussionNote(c.projectId, c.mergeId, deleteCommentRequest.DiscussionId, deleteCommentRequest.NoteId)

	if err != nil {
		c.handleError(w, err, "Could not delete comment", res.StatusCode)
		return
	}

	/* TODO: Check status code */
	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: "Comment deleted succesfully",
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)
}

func PostComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var postCommentRequest PostCommentRequest
	err = json.Unmarshal(body, &postCommentRequest)
	if err != nil {
		c.handleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
		return
	}

	position := &gitlab.NotePosition{
		PositionType: "text",
		StartSHA:     postCommentRequest.StartCommitSHA,
		HeadSHA:      postCommentRequest.HeadCommitSHA,
		BaseSHA:      postCommentRequest.BaseCommitSHA,
		NewPath:      postCommentRequest.FileName,
		OldPath:      postCommentRequest.FileName,
		NewLine:      postCommentRequest.NewLine,
		OldLine:      postCommentRequest.OldLine,
	}

	discussion, _, err := c.git.Discussions.CreateMergeRequestDiscussion(
		c.projectId,
		c.mergeId,
		&gitlab.CreateMergeRequestDiscussionOptions{
			Body:     &postCommentRequest.Comment,
			Position: position,
		})

	if err != nil {
		c.handleError(w, err, "Could not create comment", http.StatusBadRequest)
		return
	}

	response := CommentResponse{
		SuccessResponse: SuccessResponse{
			Message: "Comment updated succesfully",
			Status:  http.StatusOK,
		},
		Comment: discussion.Notes[0],
	}

	json.NewEncoder(w).Encode(response)
}

func EditComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var editCommentRequest EditCommentRequest
	err = json.Unmarshal(body, &editCommentRequest)
	if err != nil {
		c.handleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
		return
	}

	options := gitlab.UpdateMergeRequestDiscussionNoteOptions{}

	/* The PATCH can either be to the resolved status of
	the discussion or or the text of the comment */
	msg := "edit comment"
	if editCommentRequest.Comment == "" {
		options.Resolved = &editCommentRequest.Resolved
		msg = "update discussion status"
	} else {
		options.Body = gitlab.String(editCommentRequest.Comment)
	}

	note, res, err := c.git.Discussions.UpdateMergeRequestDiscussionNote(c.projectId, c.mergeId, editCommentRequest.DiscussionId, editCommentRequest.NoteId, &options)

	if err != nil {
		c.handleError(w, err, "Could not "+msg, res.StatusCode)
		return
	}

	w.WriteHeader(res.StatusCode)

	if res.StatusCode != http.StatusOK {
		c.handleError(w, errors.New("Non-200 status code recieved"), "Could not "+msg, res.StatusCode)
	}

	response := CommentResponse{
		SuccessResponse: SuccessResponse{
			Message: "Comment updated succesfully",
			Status:  http.StatusOK,
		},
		Comment: note,
	}

	json.NewEncoder(w).Encode(response)
}
