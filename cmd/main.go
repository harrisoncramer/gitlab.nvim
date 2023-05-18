package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
)

const (
	star            = "star"
	info            = "info"
	approve         = "approve"
	revoke          = "revoke"
	comment         = "comment"
	overviewComment = "overviewComment"
	deleteComment   = "deleteComment"
	editComment     = "editComment"
	reply           = "reply"
	listDiscussions = "listDiscussions"
)

func main() {

	branchName, err := getCurrentBranch()

    if err != nil {
        log.Fatalf("Failure: Failed to get current branch: %v", err)
    }

	if branchName == "main" || branchName == "master" {
		return
	}

	var c Client

    if err := c.Init(branchName); err != nil {
        log.Fatalf("Failure: Failed to iniialize client: %v", err)
    }

    if err := executeCommand(c); err != nil {
        log.Fatalf("Failure: Command execution failed: %v", err)
    }
}

func executeCommand(c Client) error {
	switch c.command {
	case star:
		return c.Star()
	case approve:
		return c.Approve()
	case revoke:
		return c.Revoke()
	case comment:
		return c.Comment()
	case deleteComment:
		return c.DeleteComment()
	case editComment:
		return c.EditComment()
	case overviewComment:
		return c.OverviewComment()
	case info:
		return c.Info()
	case reply:
		return c.Reply()
	case listDiscussions:
		return c.ListDiscussions()
	default:
		c.Usage("command")
        return nil
	}
}

/* Gets the current branch */
func getCurrentBranch() (res string, e error) {
	gitCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")

	output, err := gitCmd.Output()
	if err != nil {
		return "", fmt.Errorf("Error running git rev-parse: %w", err)
	}

	return strings.TrimSpace(string(output)), nil

}
