package main

import (
	"errors"
	"fmt"
	"os"
	"strconv"

	"github.com/xanzy/go-gitlab"
)

type Client struct {
	command   string
	projectId string
	mergeId   int
	git       *gitlab.Client
}

/* This will initialize the client with the token and check for the basic project ID and command arguments */
func (c *Client) Init(branchName string) error {

	if len(os.Args) < 3 {
		return errors.New("Must provide command and projectId")
	}

	command, projectId := os.Args[1], os.Args[2]
	c.command = command
	c.projectId = projectId

	if projectId == "" {
		return errors.New("Must provide projectId")
	}

	git, err := gitlab.NewClient(os.Getenv("GITLAB_TOKEN"))
	if err != nil {
		return fmt.Errorf("Failed to create client: %v", err)
	}

	options := gitlab.ListMergeRequestsOptions{
		State:        gitlab.String("opened"),
		SourceBranch: &branchName,
	}

	mergeRequests, _, err := git.MergeRequests.ListMergeRequests(&options)
	if err != nil {
		return fmt.Errorf("Failed to list merge requests: %w", err)
	}

	if len(mergeRequests) == 0 {
		return errors.New("No merge requests found")
	}

	mergeId := strconv.Itoa(mergeRequests[0].IID)
	mergeIdInt, err := strconv.Atoi(mergeId)
	if err != nil {
		return err
	}

	c.mergeId = mergeIdInt
	c.git = git

	return nil
}

func (c *Client) Usage(command string) {
	fmt.Printf("Usage: gitlab-nvim %s <project-id> ...args", command)
	os.Exit(1)
}
