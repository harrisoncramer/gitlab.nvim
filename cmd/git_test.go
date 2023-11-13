package main

import (
	"errors"
	"fmt"
	"testing"
)

func TestExtractGitInfo_Success(t *testing.T) {
	getCurrentBranchName := func() (string, error) {
		return "feature/abc", nil
	}
	testCases := []struct {
		getProjectRemoteUrl func() (string, error)
		expected            GitProjectInfo
		desc                string
	}{
		{
			desc: "Project configured in SSH under a single folder",
			getProjectRemoteUrl: func() (string, error) {
				return "git@custom-gitlab.com:namespace-1/project-name.git", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "git@custom-gitlab.com:namespace-1/project-name.git",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1",
			},
		},
		{
			desc: "Project configured in SSH under a single folder without .git extension",
			getProjectRemoteUrl: func() (string, error) {
				return "git@custom-gitlab.com:namespace-1/project-name", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "git@custom-gitlab.com:namespace-1/project-name",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1",
			},
		},
		{
			desc: "Project configured in SSH under one nested folder",
			getProjectRemoteUrl: func() (string, error) {
				return "git@custom-gitlab.com:namespace-1/namespace-2/project-name.git", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "git@custom-gitlab.com:namespace-1/namespace-2/project-name.git",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1/namespace-2",
			},
		},
		{
			desc: "Project configured in SSH under two nested folders",
			getProjectRemoteUrl: func() (string, error) {
				return "git@custom-gitlab.com:namespace-1/namespace-2/namespace-3/project-name.git", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "git@custom-gitlab.com:namespace-1/namespace-2/namespace-3/project-name.git",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1/namespace-2/namespace-3",
			},
		},
		{
			desc: "Project configured in SSH:// under a single folder",
			getProjectRemoteUrl: func() (string, error) {
				return "ssh://custom-gitlab.com/namespace-1/project-name.git", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "ssh://custom-gitlab.com/namespace-1/project-name.git",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1",
			},
		},
		{
			desc: "Project configured in SSH:// under a single folder without .git extension",
			getProjectRemoteUrl: func() (string, error) {
				return "ssh://custom-gitlab.com/namespace-1/project-name", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "ssh://custom-gitlab.com/namespace-1/project-name",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1",
			},
		},
		{
			desc: "Project configured in SSH:// under two nested folders",
			getProjectRemoteUrl: func() (string, error) {
				return "ssh://custom-gitlab.com/namespace-1/namespace-2/namespace-3/project-name.git", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "ssh://custom-gitlab.com/namespace-1/namespace-2/namespace-3/project-name.git",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1/namespace-2/namespace-3",
			},
		},
		{
			desc: "Project configured in HTTP and under a single folder without .git extension",
			getProjectRemoteUrl: func() (string, error) {
				return "http://custom-gitlab.com/namespace-1/project-name", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "http://custom-gitlab.com/namespace-1/project-name",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1",
			},
		},
		{
			desc: "Project configured in HTTPS and under a single folder",
			getProjectRemoteUrl: func() (string, error) {
				return "https://custom-gitlab.com/namespace-1/project-name.git", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "https://custom-gitlab.com/namespace-1/project-name.git",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1",
			},
		},
		{
			desc: "Project configured in HTTPS and under a nested folder",
			getProjectRemoteUrl: func() (string, error) {
				return "https://custom-gitlab.com/namespace-1/namespace-2/project-name.git", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "https://custom-gitlab.com/namespace-1/namespace-2/project-name.git",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1/namespace-2",
			},
		},
		{
			desc: "Project configured in HTTPS and under two nested folders",
			getProjectRemoteUrl: func() (string, error) {
				return "https://custom-gitlab.com/namespace-1/namespace-2/namespace-3/project-name.git", nil
			},
			expected: GitProjectInfo{
				RemoteUrl:   "https://custom-gitlab.com/namespace-1/namespace-2/namespace-3/project-name.git",
				BranchName:  "feature/abc",
				ProjectName: "project-name",
				Namespace:   "namespace-1/namespace-2/namespace-3",
			},
		},
	}
	for _, tC := range testCases {
		t.Run(tC.desc, func(t *testing.T) {
			actual, err := ExtractGitInfo(tC.getProjectRemoteUrl, getCurrentBranchName)
			if err != nil {
				t.Errorf("No error was expected, got %s", err)
			}
			if actual != tC.expected {
				t.Errorf("\nExpected: %s\nActual:   %s", tC.expected, actual)
			}
		})
	}
}

func TestExtractGitInfo_FailToGetProjectRemoteUrl(t *testing.T) {
	getCurrentBranchName := func() (string, error) {
		return "feature/abc", nil
	}

	testCases := []struct {
		getProjectRemoteUrl  func() (string, error)
		expectedErrorMessage string
		desc                 string
	}{
		{
			desc: "Error returned by function to get the project remote url",
			getProjectRemoteUrl: func() (string, error) {
				return "", errors.New("error when getting project remote url")
			},
			expectedErrorMessage: "Could not get project Url: error when getting project remote url",
		},
		{
			desc: "Invalid project remote url",
			getProjectRemoteUrl: func() (string, error) {
				return "git@invalid", nil
			},
			expectedErrorMessage: "Invalid Git URL format: git@invalid",
		},
	}
	for _, tC := range testCases {
		t.Run(tC.desc, func(t *testing.T) {
			_, actualErr := ExtractGitInfo(tC.getProjectRemoteUrl, getCurrentBranchName)
			if actualErr == nil {
				t.Errorf("Expected an error, got none")
			}
			if actualErr.Error() != tC.expectedErrorMessage {
				t.Errorf("\nExpected: %s\nActual:   %s", tC.expectedErrorMessage, actualErr.Error())
			}
		})
	}
}

func TestExtractGitInfo_FailToGetCurrentBranchName(t *testing.T) {
	expectedErrNestedMsg := "error when getting current branch name"
	_, actualErr := ExtractGitInfo(func() (string, error) {
		return "git@custom-gitlab.com:namespace/project.git", nil
	}, func() (string, error) {
		return "", errors.New(expectedErrNestedMsg)
	})

	if actualErr == nil {
		t.Errorf("Expected an error, got none")
	}
	expectedErr := fmt.Errorf("Failed to get current branch: %s", expectedErrNestedMsg)
	if actualErr.Error() != expectedErr.Error() {
		t.Errorf("\nExpected: %s\nActual:   %s", expectedErr, actualErr)
	}
}
