package main

import (
	"fmt"
)

func (c *Client) Approve() error {

	_, _, err := c.git.MergeRequestApprovals.ApproveMergeRequest(c.projectId, c.mergeId, nil, nil)

	if err != nil {
		return fmt.Errorf("Approving MR failed: %w", err)
	}

	fmt.Println("Success! Approved MR.")

	return nil
}
