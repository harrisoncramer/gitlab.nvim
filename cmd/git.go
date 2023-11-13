package main

import (
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

type GitProjectInfo struct {
	RemoteUrl   string
	Namespace   string
	ProjectName string
	BranchName  string
}

/*
projectPath returns the Gitlab project full path, which isn't necessarily the same as its name.
See https://docs.gitlab.com/ee/api/rest/index.html#namespaced-path-encoding for more information.
*/
func (g GitProjectInfo) projectPath() string {
	return g.Namespace + "/" + g.ProjectName
}

/*
Extracts information about the current repository and returns
it to the client for initialization. The current directory must be a valid
Gitlab project and the branch must be a feature branch
*/
func ExtractGitInfo(getProjectRemoteUrl func() (string, error), getCurrentBranchName func() (string, error)) (GitProjectInfo, error) {
	url, err := getProjectRemoteUrl()
	if err != nil {
		return GitProjectInfo{}, fmt.Errorf("Could not get project Url: %v", err)
	}

  // play with regex at: https://regex101.com/r/P2jSGh/1
	re := regexp.MustCompile(`(?:^git@.+:|^https?:\/\/.+?[^\/:]\/)(.+)\/([^\/]+)\.git$`)
	matches := re.FindStringSubmatch(url)
	if len(matches) != 3 {
		return GitProjectInfo{}, fmt.Errorf("Invalid Git URL format: %s", url)
	}

	namespace := matches[1]
	projectName := matches[2]

	branchName, err := getCurrentBranchName()
	if err != nil {
		return GitProjectInfo{}, fmt.Errorf("Failed to get current branch: %v", err)
	}

	return GitProjectInfo{
			RemoteUrl:   url,
			Namespace:   namespace,
			ProjectName: projectName,
			BranchName:  branchName,
		},
		nil
}

/* Gets the current branch name */
func GetCurrentBranchNameFromNativeGitCmd() (res string, e error) {
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
func GetProjectUrlFromNativeGitCmd() (string, error) {
	cmd := exec.Command("git", "remote", "get-url", "origin")
	url, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("Could not get origin remote")
	}

	return strings.TrimSpace(string(url)), nil
}
