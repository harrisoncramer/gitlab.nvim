package main

import (
	"errors"
	"fmt"
	"os"
	"strconv"

	"github.com/xanzy/go-gitlab"
)

type Client struct {
	command        string
	projectId      string
	mergeId        int
	gitlabInstance string
	authToken      string
	git            *gitlab.Client
}

type Logger struct {
	Active bool
}

func (l Logger) Printf(s string, args ...interface{}) {
	logString := fmt.Sprintf(s+"\n", args...)
	logPath := os.Args[len(os.Args)-1]

	file, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		panic(err)
	}
	defer file.Close()
	_, err = file.Write([]byte(logString))
}

/* This will initialize the client with the token and check for the basic project ID and command arguments */
func (c *Client) Init(branchName string) error {

	if len(os.Args) < 5 {
		return errors.New("Must provide project ID, gitlab instance, port, and auth token!")
	}

	projectId := os.Args[1]
	gitlabInstance := os.Args[2]
	authToken := os.Args[4]

	if projectId == "" {
		return errors.New("Project ID cannot be empty")
	}

	if gitlabInstance == "" {
		return errors.New("GitLab instance URL cannot be empty")
	}

	if authToken == "" {
		return errors.New("Auth token cannot be empty")
	}

	c.gitlabInstance = gitlabInstance
	c.projectId = projectId
	c.authToken = authToken

	var l Logger
	var apiCustUrl = fmt.Sprintf(c.gitlabInstance + "/api/v4")

	git, err := gitlab.NewClient(authToken, gitlab.WithBaseURL(apiCustUrl), gitlab.WithCustomLogger(l))

	if err != nil {
		return fmt.Errorf("Failed to create client: %v", err)
	}

	options := gitlab.ListMergeRequestsOptions{
		Scope:        gitlab.String("all"),
		State:        gitlab.String("opened"),
		SourceBranch: &branchName,
	}

	mergeRequests, _, err := git.MergeRequests.ListMergeRequests(&options)
	if err != nil {
		return fmt.Errorf("Failed to list merge requests: %w", err)
	}

	if len(mergeRequests) == 0 {
		return errors.New("No merge requests found")
	}

	mergeId := strconv.Itoa(mergeRequests[0].IID)
	mergeIdInt, err := strconv.Atoi(mergeId)
	if err != nil {
		return err
	}

	c.mergeId = mergeIdInt
	c.git = git

	return nil
}
