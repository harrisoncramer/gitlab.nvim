package main

import (
	"fmt"
)

func (c *Client) Revoke() error {

	_, err := c.git.MergeRequestApprovals.UnapproveMergeRequest(c.projectId, c.mergeId, nil, nil)

	if err != nil {
		return fmt.Errorf("Revoking approval failed: %w", err)
	}

	fmt.Println("Success! Revoked MR approval.")

	return nil
}
