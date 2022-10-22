package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"

	"github.com/xanzy/go-gitlab"
)

func (c *Client) EditComment() error {
	if len(os.Args) < 6 {
		return errors.New("Must provide commentId, noteId, and edited text")
	}

	discussionId, noteId, newCommentText := os.Args[3], os.Args[4], os.Args[5]
	if discussionId == "" || newCommentText == "" {
		return errors.New("Must provide commentId, noteId, and edited text")
	}

	options := gitlab.UpdateMergeRequestDiscussionNoteOptions{
		Body: gitlab.String(newCommentText),
	}

	noteIdInt, err := strconv.Atoi(noteId)
	if err != nil {
		return errors.New("Not a valid noteId")
	}

	gitlabNote, _, err := c.git.Discussions.UpdateMergeRequestDiscussionNote(c.projectId, c.mergeId, discussionId, noteIdInt, &options)

	if err != nil {
		return fmt.Errorf("Failed to edit comment: %w", err)
	}

	note, err := json.Marshal(gitlabNote)
	if err != nil {
		return fmt.Errorf("Failed to marshal note: %w", err)
	}

	fmt.Println(string(note))

	return nil
}
