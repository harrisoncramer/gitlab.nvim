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

	re := regexp.MustCompile(`(\w+://)(.+@)*([\w\d\.]+)(:[\d]+){0,1}/*(.*)`)
	matches := re.FindStringSubmatch(url)
	// matches[0] - url itself
	// matches[1] - protocol (ssh, http(s))
	// matches[2] - user (in case of ssh)
	// matches[3] - gitlab server name
	// matches[4] - port
	// matches[5] - project full path
	// i.e. 'https://gitlab.organization.com/some.compex.path.to/project.git' will be parsed as
	// matches[0] - https://gitlab.organization.com/some.compex.path.to/project.git
	// matches[1] - http://
	// matches[2] -
	// matches[3] - gitlab.organization.com
	// matches[4] -
	// matches[5] - some.complex.path.to/project.git
	if len(matches) != 6 || matches[5] == "" {
		return "", "", "", fmt.Errorf("Failed to retrieve project path from Git URL: %s", url)
	}

	projectPath := strings.TrimSuffix(matches[5], ".git")

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
