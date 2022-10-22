package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/xanzy/go-gitlab"
)

func (c *Client) Reply() error {

	if len(os.Args) < 5 {
		return errors.New("Must provide discussionId and reply text")
	}

	discussionId, reply := os.Args[3], os.Args[4]

	now := time.Now()
	options := gitlab.AddMergeRequestDiscussionNoteOptions{
		Body:      gitlab.String(reply),
		CreatedAt: &now,
	}

	gitlabNote, _, err := c.git.Discussions.AddMergeRequestDiscussionNote(c.projectId, c.mergeId, discussionId, &options)

	if err != nil {
		return fmt.Errorf("Could not leave reply: %w", err)
	}

	output, err := json.Marshal(gitlabNote)
	if err != nil {
		return fmt.Errorf("Could not marshal note: %w", err)
	}

	fmt.Println(string(output))

	return nil
}
