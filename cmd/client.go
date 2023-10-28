package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"

	"github.com/hashicorp/go-retryablehttp"
	"github.com/xanzy/go-gitlab"
)

type Client struct {
	command        string
	projectId      string
	mergeId        int
	gitlabInstance string
	authToken      string
	logPath        string
	debug          bool
	git            *gitlab.Client
}

var requestLogger retryablehttp.RequestLogHook = func(l retryablehttp.Logger, r *http.Request, i int) {
	logPath := os.Args[len(os.Args)-1]

	file, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		panic(err)
	}
	defer file.Close()

	clonedRequest := r.Clone(r.Context())
	var data []byte
	reader := bufio.NewReader(clonedRequest.Body)
	_, err = reader.Read(data)
	if err != nil {
		panic(err)
	}

	clonedRequest.Header.Set("Private-Token", "xxxx")
	output := map[string]interface{}{
		"Method":  clonedRequest.Method,
		"URL":     clonedRequest.URL.String(),
		"Body":    string(data),
		"Headers": clonedRequest.Header,
	}

	logString, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		panic(err)
	}

	_, err = file.Write([]byte("-- REQUEST: \n"))
	_, err = file.Write(logString)
	_, err = file.Write([]byte("\n"))
}

var responseLogger retryablehttp.ResponseLogHook = func(l retryablehttp.Logger, response *http.Response) {
	logPath := os.Args[len(os.Args)-1]

	file, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		panic(err)
	}
	defer file.Close()

	if response.StatusCode != http.StatusOK {
		fmt.Println("HTTP request failed with status code:", response.Status)
		return
	}

	var data []byte
	reader := bufio.NewReader(response.Body)
	_, err = reader.Read(data)
	if err != nil {
		panic(err)
	}

	output := map[string]interface{}{
		"Body":    string(data),
		"Headers": response.Header,
	}

	logString, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		panic(err)
	}

	_, err = file.Write([]byte("-- RESPONSE: \n"))
	_, err = file.Write(logString)
	_, err = file.Write([]byte("\n"))
}

/* This will initialize the client with the token and check for the basic project ID and command arguments */
func (c *Client) init(branchName string) error {

	if len(os.Args) < 5 {
		return errors.New("Must provide project ID, gitlab instance, port, and auth token!")
	}

	projectId := os.Args[1]
	gitlabInstance := os.Args[2]
	authToken := os.Args[4]
	debugType := os.Args[5]

	logPath := os.Args[len(os.Args)-1]

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
	c.logPath = logPath

	var apiCustUrl = fmt.Sprintf(c.gitlabInstance + "/api/v4")

	gitlabOptions := []gitlab.ClientOptionFunc{
		gitlab.WithBaseURL(apiCustUrl),
	}

	if debugType == "request" || debugType == "both" {
		gitlabOptions = append(gitlabOptions, gitlab.WithRequestLogHook(requestLogger))
	}

	if debugType == "response" || debugType == "both" {
		gitlabOptions = append(gitlabOptions, gitlab.WithResponseLogHook(responseLogger))
	}

	git, err := gitlab.NewClient(authToken, gitlabOptions...)

	if err != nil {
		return fmt.Errorf("Failed to create client: %v", err)
	}

	options := gitlab.ListProjectMergeRequestsOptions{
		Scope:        gitlab.String("all"),
		State:        gitlab.String("opened"),
		SourceBranch: &branchName,
	}

	mergeRequests, _, err := git.MergeRequests.ListProjectMergeRequests(c.projectId, &options)
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

func (c *Client) handleError(w http.ResponseWriter, err error, message string, status int) {
	w.WriteHeader(status)
	response := ErrorResponse{
		Message: message,
		Details: err.Error(),
		Status:  status,
	}
	json.NewEncoder(w).Encode(response)
}
