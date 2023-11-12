package main

import (
	"fmt"
	"os/exec"
	"regexp"
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
func getProjectUrl() (res string, e error) {
	cmd := exec.Command("git", "remote", "get-url", "origin")
	url, err := cmd.Output()

	if err != nil {
		return "", fmt.Errorf("Could not get origin remote")
	}

	return strings.TrimSpace(string(url)), nil
}

func ExtractGitInfo() (string, string, string, error) {

	url, err := getProjectUrl()
	if err != nil {
		return "", "", "", fmt.Errorf("Could not get project Url: %v", err)
	}

	re := regexp.MustCompile(`(?:[:\/])([^\/]+)\/([^\/]+)\.git$`)
	matches := re.FindStringSubmatch(url)
	if len(matches) != 3 {
		return "", "", "", fmt.Errorf("Invalid Git URL format: %s", url)
	}

	namespace := matches[1]
	projectName := matches[2]

	return url, namespace, projectName, nil
}
