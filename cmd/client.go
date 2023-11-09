package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httputil"
	"os"
	"strconv"

	"github.com/hashicorp/go-retryablehttp"
	"github.com/xanzy/go-gitlab"
)

type Client struct {
	projectId      string
	mergeId        int
	gitlabInstance string
	authToken      string
	logPath        string
	git            *gitlab.Client
}

type DebugSettings struct {
	GoRequest  bool `json:"go_request"`
	GoResponse bool `json:"go_response"`
}

var requestLogger retryablehttp.RequestLogHook = func(l retryablehttp.Logger, r *http.Request, i int) {
	logPath := os.Args[len(os.Args)-1]

	file, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		panic(err)
	}
	defer file.Close()

	token := r.Header.Get("Private-Token")
	r.Header.Set("Private-Token", "REDACTED")
	res, err := httputil.DumpRequest(r, true)
	if err != nil {
		panic(err)
	}
	r.Header.Set("Private-Token", token)

	_, err = file.Write([]byte("\n-- REQUEST --\n")) //nolint:all
	_, err = file.Write(res)                         //nolint:all
	_, err = file.Write([]byte("\n"))                //nolint:all
}

var responseLogger retryablehttp.ResponseLogHook = func(l retryablehttp.Logger, response *http.Response) {
	logPath := os.Args[len(os.Args)-1]

	file, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		panic(err)
	}
	defer file.Close()

	res, err := httputil.DumpResponse(response, true)
	if err != nil {
		panic(err)
	}

	_, err = file.Write([]byte("\n-- RESPONSE --\n")) //nolint:all
	_, err = file.Write(res)                          //nolint:all
	_, err = file.Write([]byte("\n"))                 //nolint:all
}

/* This will initialize the client with the token and check for the basic project ID and command arguments */
func (c *Client) init(branchName string, projectName string) error {

	if len(os.Args) < 3 {
		return errors.New("Must provide gitlab instance, port, and auth token!")
	}

	gitlabInstance := os.Args[1]
	authToken := os.Args[3]
	debugSettings := os.Args[4]

	var debugObject DebugSettings
	err := json.Unmarshal([]byte(debugSettings), &debugObject)
	if err != nil {
		return fmt.Errorf("Could not parse debug settings: %w, %s", err, debugSettings)
	}

	logPath := os.Args[len(os.Args)-1]

	if gitlabInstance == "" {
		return errors.New("GitLab instance URL cannot be empty")
	}

	if authToken == "" {
		return errors.New("Auth token cannot be empty")
	}

	c.gitlabInstance = gitlabInstance
	c.authToken = authToken
	c.logPath = logPath

	var apiCustUrl = fmt.Sprintf(c.gitlabInstance + "/api/v4")

	gitlabOptions := []gitlab.ClientOptionFunc{
		gitlab.WithBaseURL(apiCustUrl),
	}

	if debugObject.GoRequest {
		gitlabOptions = append(gitlabOptions, gitlab.WithRequestLogHook(requestLogger))
	}

	if debugObject.GoResponse {
		gitlabOptions = append(gitlabOptions, gitlab.WithResponseLogHook(responseLogger))
	}

	git, err := gitlab.NewClient(authToken, gitlabOptions...)

	if err != nil {
		return fmt.Errorf("Failed to create client: %v", err)
	}

	opt := gitlab.ListProjectsOptions{
		Search:     gitlab.String(projectName),
		Membership: gitlab.Bool(true),
	}

	projects, _, err := git.Projects.ListProjects(&opt)
	if err != nil {
		return fmt.Errorf(fmt.Sprintf("Could not find project named %s", projectName), err)
	}

	if len(projects) > 1 {
		return fmt.Errorf("Query for \"%s\" returned %d projects, should return 1", projectName, len(projects))
	}

	if len(projects) == 0 {
		return fmt.Errorf("Query for \"%s\" returned no projects, should return 1", projectName)
	}

	c.projectId = fmt.Sprint(projects[0].ID)

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

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		c.handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
