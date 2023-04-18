package main

import (
	"fmt"
)

func (c *Client) Approve() error {

	_, _, err := c.git.MergeRequestApprovals.ApproveMergeRequest(c.projectId, c.mergeId, nil, nil)

	if err != nil {
		return fmt.Errorf("Approving project failed: %w", err)
	}

	fmt.Println("Success! Approved project.")

	return nil
}
