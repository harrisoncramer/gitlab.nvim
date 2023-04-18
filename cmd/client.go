package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/xanzy/go-gitlab"
)

type Client struct {
	command   string
	projectId string
	mergeId   int
	git       *gitlab.Client
}

/* This will initialize the client with the token and check for the basic project ID and command arguments */
func (c *Client) Init() error {

	if len(os.Args) < 3 {
		c.Usage()
	}

	command, projectId := os.Args[1], os.Args[2]
	c.command = command
	c.projectId = projectId

	if projectId == "" {
		c.Usage()
	}

	git, err := gitlab.NewClient(os.Getenv("GITLAB_TOKEN"))
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}

	mergeId, err := getCurrentMergeId()
	if err != nil {
		return err
	}

	mergeIdInt, err := strconv.Atoi(mergeId)
	if err != nil {
		return err
	}

	c.mergeId = mergeIdInt
	c.git = git

	return nil
}

func (c *Client) Usage() {
	log.Fatalf("Usage: gitlab-nvim <command> <project-id> <args?>")
}

/* Gets the current merge request ID from local Git */
func getCurrentMergeId() (res string, e error) {
	gitCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")

	output, err := gitCmd.Output()
	if err != nil {
		return "", fmt.Errorf("Error running git rev-parse: %w", err)
	}

	sourceBranch := strings.TrimSpace(string(output))

	glabCmd := exec.Command("bash", "-c", `glab mr list --source-branch=`+sourceBranch+` | cat | head -n3 | tail -n 1 | awk '{print $1}' | cut -c 2`)

	output, err = glabCmd.Output()
	if err != nil {
		return "", fmt.Errorf("Error running the command: %w", err)
	}

	result := strings.TrimSpace(string(output))

	return result, nil

}
