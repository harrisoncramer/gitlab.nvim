package main

import (
	"fmt"
	"log"
)

func (c *Client) Star() error {
	project, _, err := c.git.Projects.StarProject(c.projectId)
	if err != nil {
		return fmt.Errorf("Starring project failed: %w", err)
	}

	log.Printf("Success! Starred project: %s", project.Name)

	return nil
}
