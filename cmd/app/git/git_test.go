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
	branch      string
	projectName string
	namespace   string
	remote      string
}

func TestExtractGitInfo_Success(t *testing.T) {
	testCases := []TestCase{
		{
			desc:        "Project configured in SSH under a single folder",
			remote:      "git@custom-gitlab.com:namespace-1/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in SSH under a single folder without .git extension",
			remote:      "git@custom-gitlab.com:namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in SSH under one nested folder",
			remote:      "git@custom-gitlab.com:namespace-1/namespace-2/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2",
		},
		{
			desc:        "Project configured in SSH under two nested folders",
			remote:      "git@custom-gitlab.com:namespace-1/namespace-2/namespace-3/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2/namespace-3",
		},
		{
			desc:        "Project configured in SSH:// under a single folder",
			remote:      "ssh://custom-gitlab.com/namespace-1/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in SSH:// under a single folder without .git extension",
			remote:      "ssh://custom-gitlab.com/namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in SSH:// under two nested folders",
			remote:      "ssh://custom-gitlab.com/namespace-1/namespace-2/namespace-3/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2/namespace-3",
		},
		{
			desc:        "Project configured in SSH:// and have a custom port",
			remote:      "ssh://custom-gitlab.com:2222/namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in HTTP and under a single folder without .git extension",
			remote:      "http://custom-gitlab.com/namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in HTTP and under a single folder without .git extension (with embedded credentials)",
			remote:      "http://username:password@custom-gitlab.com/namespace-1/project-name",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in HTTPS and under a single folder",
			remote:      "https://custom-gitlab.com/namespace-1/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in HTTPS and under a single folder (with embedded credentials)",
			remote:      "https://username:password@custom-gitlab.com/namespace-1/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1",
		},
		{
			desc:        "Project configured in HTTPS and under a nested folder",
			remote:      "https://custom-gitlab.com/namespace-1/namespace-2/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2",
		},
		{
			desc:        "Project configured in HTTPS and under a nested folder (with embedded credentials)",
			remote:      "https://username:password@custom-gitlab.com/namespace-1/namespace-2/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2",
		},
		{
			desc:        "Project configured in HTTPS and under two nested folders",
			remote:      "https://custom-gitlab.com/namespace-1/namespace-2/namespace-3/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2/namespace-3",
		},
		{
			desc:        "Project configured in HTTPS and under two nested folders (with embedded credentials)",
			remote:      "https://username:password@custom-gitlab.com/namespace-1/namespace-2/namespace-3/project-name.git",
			branch:      "feature/abc",
			projectName: "project-name",
			namespace:   "namespace-1/namespace-2/namespace-3",
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
			data, err := NewGitData(tC.remote, g)
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
		expectedErr: "Could not get project Url: Some error",
	}
	t.Run(tC.desc, func(t *testing.T) {
		g := failingUrlManager{
			errMsg: tC.errMsg,
		}
		_, err := NewGitData("", g)
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
		expectedErr: "Failed to get current branch: Some error",
	}
	t.Run(tC.desc, func(t *testing.T) {
		g := failingBranchManager{
			FakeGitManager: FakeGitManager{
				RemoteUrl: "git@custom-gitlab.com:namespace-1/project-name.git",
			},
			errMsg: tC.errMsg,
		}
		_, err := NewGitData("", g)
		if err == nil {
			t.Errorf("Expected an error, got none")
		}
		if err.Error() != tC.expectedErr {
			t.Errorf("\nExpected: %s\nActual:   %s", tC.expectedErr, err.Error())
		}
	})
}
