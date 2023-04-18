package main

import (
	"fmt"
	"os"

	"github.com/xanzy/go-gitlab"
)

func (c *Client) Comment() error {
	if len(os.Args) < 4 {
		c.Usage()
	}
	comment := os.Args[3]
	if comment == "" {
		return fmt.Errorf("Comment cannot be empty")
	}

	var note gitlab.CreateMergeRequestNoteOptions
	note.Body = gitlab.String(comment)

	_, _, err := c.git.Notes.CreateMergeRequestNote(c.projectId, c.mergeId, &note, nil)

	if err != nil {
		return fmt.Errorf("Approving project failed: %w", err)
	}

	fmt.Println("Comment: " + comment[0:15])

	return nil
}
