package main

import (
	"fmt"
	"os/exec"
	"strings"
)

/* Gets the current branch */
func GetCurrentBranch() (res string, e error) {
	gitCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")

	output, err := gitCmd.Output()
	if err != nil {
		return "", fmt.Errorf("Error running git rev-parse: %w", err)
	}

	return strings.TrimSpace(string(output)), nil
}

/* Gets the project SSH or HTTPS url */
func GetProjectName() (res string, e error) {
	cmd := exec.Command("git", "remote", "get-url", "origin")
	url, err := cmd.Output()

	if err != nil {
		return "", fmt.Errorf("Could not get origin remote")
	}

	return strings.TrimSpace(string(url)), nil
}
