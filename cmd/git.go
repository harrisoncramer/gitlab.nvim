package main

import (
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

/*
Extracts information about the current repository and returns
it to the client for initialization. The current directory must be a valid
Gitlab project and the branch must be a feature branch
*/
func ExtractGitInfo() (string, string, string, error) {

	url, err := getProjectUrl()
	if err != nil {
		return "", "", "", fmt.Errorf("Could not get project Url: %v", err)
	}

	re := regexp.MustCompile(`(\w+://)(.+@)*([\w\d\.]+)(:[\d]+){0,1}/*(.*)\.git`)
	matches := re.FindStringSubmatch(url)
	if len(matches) > 5 {
		return "", "", "", fmt.Errorf("Invalid Git URL format: %s", url)
	}

	projectPath := matches[5]

	branch, err := getCurrentBranch()
	if err != nil {
		return "", "", "", fmt.Errorf("Failed to get current branch: %v", err)
	}

	return url, projectPath, branch, nil
}

/* Gets the current branch */
func getCurrentBranch() (res string, e error) {
	gitCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")

	output, err := gitCmd.Output()
	if err != nil {
		return "", fmt.Errorf("Error running git rev-parse: %w", err)
	}

	branchName := strings.TrimSpace(string(output))

	if branchName == "main" || branchName == "master" {
		return "", fmt.Errorf("Cannot run on %s branch", branchName)
	}

	return branchName, nil
}

/* Gets the project SSH or HTTPS url */
func getProjectUrl() (res string, e error) {
	cmd := exec.Command("git", "remote", "get-url", "origin")
	url, err := cmd.Output()

	if err != nil {
		return "", fmt.Errorf("Could not get origin remote")
	}

	return strings.TrimSpace(string(url)), nil
}
