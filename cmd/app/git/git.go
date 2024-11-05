package git

import (
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

type GitManager interface {
	RefreshProjectInfo(remote string) error
	GetProjectUrlFromNativeGitCmd(remote string) (url string, err error)
	GetCurrentBranchNameFromNativeGitCmd() (string, error)
	GetLatestCommitOnRemote(remote string, branchName string) (string, error)
}

type GitData struct {
	RemoteUrl   string
	Namespace   string
	ProjectName string
	BranchName  string
}

type Git struct{}

/*
projectPath returns the Gitlab project full path, which isn't necessarily the same as its name.
See https://docs.gitlab.com/ee/api/rest/index.html#namespaced-path-encoding for more information.
*/
func (g GitData) ProjectPath() string {
	return g.Namespace + "/" + g.ProjectName
}

/*
Extracts information about the current repository and returns
it to the client for initialization. The current directory must be a valid
Gitlab project and the branch must be a feature branch
*/
func NewGitData(remote string, gitlabUrl string, g GitManager) (GitData, error) {
	err := g.RefreshProjectInfo(remote)
	if err != nil {
		return GitData{}, fmt.Errorf("could not get latest information from remote: %v", err)
	}

	url, err := g.GetProjectUrlFromNativeGitCmd(remote)
	if err != nil {
		return GitData{}, fmt.Errorf("could not get project Url: %v", err)
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
	re := regexp.MustCompile(`^(?:git@[^\/:]*|https?:\/\/[^\/]+|ssh:\/\/[^\/:]+)(?::\d+)?[\/:](.*)\/([^\/]+?)(?:\.git)?\/?$`)
	matches := re.FindStringSubmatch(url)
	if len(matches) != 3 {
		return GitData{}, fmt.Errorf("invalid git URL format: %s", url)
	}

	// remove part of the hostname from the parsed namespace
	url_re := regexp.MustCompile(`[^\/]\/([^\/].*)$`)
	url_matches := url_re.FindStringSubmatch(gitlabUrl)
	var namespace string = matches[1]
	if len(url_matches) == 2 {
		namespace = strings.TrimLeft(strings.TrimPrefix(namespace, url_matches[1]), "/")
	}

	projectName := matches[2]

	branchName, err := g.GetCurrentBranchNameFromNativeGitCmd()
	if err != nil {
		return GitData{}, fmt.Errorf("failed to get current branch: %v", err)
	}

	return GitData{
			RemoteUrl:   url,
			Namespace:   namespace,
			ProjectName: projectName,
			BranchName:  branchName,
		},
		nil
}

/* Gets the current branch name */
func (g Git) GetCurrentBranchNameFromNativeGitCmd() (res string, e error) {
	gitCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")

	output, err := gitCmd.Output()
	if err != nil {
		return "", fmt.Errorf("error running git rev-parse: %w", err)
	}

	branchName := strings.TrimSpace(string(output))

	return branchName, nil
}

/* Gets the project SSH or HTTPS url */
func (g Git) GetProjectUrlFromNativeGitCmd(remote string) (string, error) {
	cmd := exec.Command("git", "remote", "get-url", remote)
	url, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("could not get remote")
	}

	return strings.TrimSpace(string(url)), nil
}

/* Pulls down latest commit information from Gitlab */
func (g Git) RefreshProjectInfo(remote string) error {
	cmd := exec.Command("git", "fetch", remote)
	_, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("failed to run `git fetch %s`: %v", remote, err)
	}

	return nil
}

func (g Git) GetLatestCommitOnRemote(remote string, branchName string) (string, error) {
	cmd := exec.Command("git", "log", "-1", "--format=%H", fmt.Sprintf("%s/%s", remote, branchName))

	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to run `git log -1 --format=%%H %s/%s`", remote, branchName)
	}

	commit := strings.TrimSpace(string(out))
	return commit, nil
}
