package git

import (
	"errors"
	"testing"
)

type FakeGitManager struct {
	RemoteUrl   string
	BranchName  string
	ProjectName string
	Namespace   string
}

func (f FakeGitManager) RefreshProjectInfo(remote string) error {
	return nil
}

func (f FakeGitManager) GetCurrentBranchNameFromNativeGitCmd() (string, error) {
	return f.BranchName, nil
}

func (f FakeGitManager) GetLatestCommitOnRemote(remote string, branchName string) (string, error) {
	return "", nil
}

func (f FakeGitManager) GetProjectUrlFromNativeGitCmd(string) (url string, err error) {
	return f.RemoteUrl, nil
}

type TestCase struct {
	desc        string
	url         string
	branch      string
	projectName string
	namespace   string
	remote      string
}

func TestExtractGitInfo_Success(t *testing.T) {
	testCases := []TestCase{
		{
			desc:        "Project configured in SSH under a single folder",
			url:         "git@custom-gitlab.com",
			remote:      "git@custom-gitlab.com:namespace-1/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in SSH under a single folder without .git extension",
			url:         "git@custom-gitlab.com",
			remote:      "git@custom-gitlab.com:namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in SSH under one nested folder",
			url:         "git@custom-gitlab.com",
			remote:      "git@custom-gitlab.com:namespace-1/namespace-2/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2",
		},
		{
			desc:        "Project configured in SSH under two nested folders",
			url:         "git@custom-gitlab.com",
			remote:      "git@custom-gitlab.com:namespace-1/namespace-2/namespace-3/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2/namespace-3",
		},
		{
			desc:        "Project configured in SSH:// under a single folder",
			url:         "ssh://custom-gitlab.com",
			remote:      "ssh://custom-gitlab.com/namespace-1/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in SSH:// under a single folder without .git extension",
			url:         "ssh://custom-gitlab.com",
			remote:      "ssh://custom-gitlab.com/namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in SSH:// under two nested folders",
			url:         "ssh://custom-gitlab.com",
			remote:      "ssh://custom-gitlab.com/namespace-1/namespace-2/namespace-3/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2/namespace-3",
		},
		{
			desc:        "Project configured in SSH:// and have a custom port",
			url:         "ssh://custom-gitlab.com",
			remote:      "ssh://custom-gitlab.com:2222/namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in SSH:// and have a custom port (with gitlab url namespace)",
			url:         "ssh://custom-gitlab.com/a",
			remote:      "ssh://custom-gitlab.com:2222/a/namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in HTTP and under a single folder without .git extension",
			url:         "http://custom-gitlab.com",
			remote:      "http://custom-gitlab.com/namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in HTTP and under a single folder without .git extension (with embedded credentials)",
			url:         "http://custom-gitlab.com",
			remote:      "http://username:password@custom-gitlab.com/namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in HTTPS and under a single folder",
			url:         "https://custom-gitlab.com",
			remote:      "https://custom-gitlab.com/namespace-1/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in HTTPS and under a single folder (with embedded credentials)",
			url:         "https://custom-gitlab.com",
			remote:      "https://username:password@custom-gitlab.com/namespace-1/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in HTTPS and under a nested folder",
			url:         "https://custom-gitlab.com",
			remote:      "https://custom-gitlab.com/namespace-1/namespace-2/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2",
		},
		{
			desc:        "Project configured in HTTPS and under a nested folder (with embedded credentials)",
			url:         "https://custom-gitlab.com",
			remote:      "https://username:password@custom-gitlab.com/namespace-1/namespace-2/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2",
		},
		{
			desc:        "Project configured in HTTPS and under two nested folders",
			url:         "https://custom-gitlab.com",
			remote:      "https://custom-gitlab.com/namespace-1/namespace-2/namespace-3/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2/namespace-3",
		},
		{
			desc:        "Project configured in HTTPS and under two nested folders (with embedded credentials)",
			url:         "https://custom-gitlab.com",
			remote:      "https://username:password@custom-gitlab.com/namespace-1/namespace-2/namespace-3/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2/namespace-3",
		},
		{
			desc:        "Project configured in HTTPS and under one nested folders (with gitlab url namespace)",
			url:         "https://custom-gitlab.com/gitlab",
			remote:      "https://username:password@custom-gitlab.com/gitlab/namespace-2/namespace-3/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-2/namespace-3",
		},
		{
			desc:        "Project configured in HTTPS and under one nested folders (with gitlab url namespace + extra slash)",
			url:         "https://custom-gitlab.com/gitlab/",
			remote:      "https://username:password@custom-gitlab.com/gitlab/namespace-2/namespace-3/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-2/namespace-3",
		},
	}
	for _, tC := range testCases {
		t.Run(tC.desc, func(t *testing.T) {
			g := FakeGitManager{
				Namespace:   tC.namespace,
				ProjectName: tC.projectName,
				BranchName:  tC.branch,
				RemoteUrl:   tC.remote,
			}
			data, err := NewGitData(tC.remote, tC.url, g)
			if err != nil {
				t.Errorf("No error was expected, got %s", err)
			}
			if data.RemoteUrl != tC.remote {
				t.Errorf("\nExpected Remote URL: %s\nActual:   %s", tC.remote, data.RemoteUrl)
			}
			if data.BranchName != tC.branch {
				t.Errorf("\nExpected Branch Name: %s\nActual:   %s", tC.branch, data.BranchName)
			}
			if data.ProjectName != tC.projectName {
				t.Errorf("\nExpected Project Name: %s\nActual:   %s", tC.projectName, data.ProjectName)
			}
			if data.Namespace != tC.namespace {
				t.Errorf("\nExpected Namespace: %s\nActual:   %s", tC.namespace, data.Namespace)
			}
		})
	}
}

type FailTestCase struct {
	desc        string
	errMsg      string
	expectedErr string
}

type failingUrlManager struct {
	errMsg string
	FakeGitManager
}

func (f failingUrlManager) GetProjectUrlFromNativeGitCmd(string) (string, error) {
	return "", errors.New(f.errMsg)
}

func TestExtractGitInfo_FailToGetProjectRemoteUrl(t *testing.T) {
	tC := FailTestCase{
		desc:        "Error returned by function to get the project remote url",
		errMsg:      "Some error",
		expectedErr: "could not get project Url: Some error",
	}
	t.Run(tC.desc, func(t *testing.T) {
		g := failingUrlManager{
			errMsg: tC.errMsg,
		}
		_, err := NewGitData("", "", g)
		if err == nil {
			t.Errorf("Expected an error, got none")
		}
		if err.Error() != tC.expectedErr {
			t.Errorf("\nExpected: %s\nActual:   %s", tC.expectedErr, err.Error())
		}
	})
}

type failingBranchManager struct {
	errMsg string
	FakeGitManager
}

func (f failingBranchManager) GetCurrentBranchNameFromNativeGitCmd() (string, error) {
	return "", errors.New(f.errMsg)
}

func TestExtractGitInfo_FailToGetCurrentBranchName(t *testing.T) {
	tC := FailTestCase{
		desc:        "Error returned by function to get the project remote url",
		errMsg:      "Some error",
		expectedErr: "failed to get current branch: Some error",
	}
	t.Run(tC.desc, func(t *testing.T) {
		g := failingBranchManager{
			FakeGitManager: FakeGitManager{
				RemoteUrl: "git@custom-gitlab.com:namespace-1/project-name.git",
			},
			errMsg: tC.errMsg,
		}
		_, err := NewGitData("", "", g)
		if err == nil {
			t.Errorf("Expected an error, got none")
		}
		if err.Error() != tC.expectedErr {
			t.Errorf("\nExpected: %s\nActual:   %s", tC.expectedErr, err.Error())
		}
	})
}
