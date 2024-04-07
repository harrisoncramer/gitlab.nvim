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
func extractGitInfo(refreshGitInfo func() error, getProjectRemoteUrl func() (string, error), getCurrentBranchName func() (string, error)) (GitProjectInfo, error) {

	err := refreshGitInfo()
	if err != nil {
		return GitProjectInfo{}, fmt.Errorf("Could not get latest information from remote: %v", err)
	}

	url, err := getProjectRemoteUrl()

	if err != nil {
		return GitProjectInfo{}, fmt.Errorf("Could not get project Url: %v", err)
	}

	/*
	   This should match following formats:
	       namespace: namespace, projectName: dummy-test-repo:
	           https://gitlab.com/namespace/dummy-test-repo.git
	           git@gitlab.com:namespace/dummy-test-repo.git
	           ssh://git@gitlab.com/namespace/dummy-test-repo.git

	       namespace: namespace/subnamespace, projectName: dummy-test-repo:
	           ssh://git@gitlab.com/namespace/subnamespace/dummy-test-repo
	           https://git@gitlab.com/namespace/subnamespace/dummy-test-repo.git
	           git@git@gitlab.com:namespace/subnamespace/dummy-test-repo.git
	*/
	re := regexp.MustCompile(`(?:^https?:\/\/|^ssh:\/\/|^git@)(?:[^\/:]+)[\/:](.*)\/([^\/]+?)(?:\.git)?$`)
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

/* Pulls down latest commit information from Gitlab */
func RefreshProjectInfo() error {
	cmd := exec.Command("git", "fetch", "origin")
	_, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("Failed to run `git fetch origin`: %v", err)
	}

	return nil
}
