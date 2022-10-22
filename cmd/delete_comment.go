package main

import (
	"fmt"
	"os"
	"strconv"
)

func (c *Client) DeleteComment() error {
	discussionId, noteId := os.Args[3], os.Args[4]
	if discussionId == "" || noteId == "" {
		c.Usage("deleteComment")
	}

	noteIdInt, err := strconv.Atoi(noteId)
	if err != nil {
		return fmt.Errorf("Could not convert noteId to int: %w", err)
	}

	_, err = c.git.Discussions.DeleteMergeRequestDiscussionNote(c.projectId, c.mergeId, discussionId, noteIdInt)

	if err != nil {
		return fmt.Errorf("Could not delete comment: %w", err)
	}

	fmt.Println("Deleted comment")

	return nil
}
