package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
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
	git            *gitlab.Client
}

type DebugSettings struct {
	GoRequest  bool `json:"go_request"`
	GoResponse bool `json:"go_response"`
}

/* This will parse and validate the project settings and then initialize the Gitlab client */
func (c *Client) initGitlabClient() error {

	if len(os.Args) < 6 {
		return errors.New("Must provide gitlab url, port, auth token, debug settings, and log path")
	}

	gitlabInstance := os.Args[1]
	if gitlabInstance == "" {
		return errors.New("GitLab instance URL cannot be empty")
	}

	authToken := os.Args[3]
	if authToken == "" {
		return errors.New("Auth token cannot be empty")
	}

	/* Parse debug settings and initialize logger handlers */
	debugSettings := os.Args[4]
	var debugObject DebugSettings
	err := json.Unmarshal([]byte(debugSettings), &debugObject)
	if err != nil {
		return fmt.Errorf("Could not parse debug settings: %w, %s", err, debugSettings)
	}

	var apiCustUrl = fmt.Sprintf(gitlabInstance + "/api/v4")

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

	c.gitlabInstance = gitlabInstance
	c.authToken = authToken
	c.git = git

	return nil
}

/* This will fetch the project ID and merge request ID using the client */
func (c *Client) initProjectSettings(branchName string, remoteUrl string) error {

	opt := gitlab.ListProjectsOptions{
		Simple:     gitlab.Bool(true),
		Membership: gitlab.Bool(true),
	}

	projects, _, err := c.git.Projects.ListProjects(&opt)
	if err != nil {
		return fmt.Errorf(fmt.Sprintf("Could not find project named %s", remoteUrl), err)
	}

	if len(projects) == 0 {
		return fmt.Errorf("Query for \"%s\" returned no projects", remoteUrl)
	}

	var project *gitlab.Project
	for _, p := range projects {
		if p.SSHURLToRepo == remoteUrl || p.HTTPURLToRepo == remoteUrl {
			project = p
			break
		}
	}

	if project == nil {
		return fmt.Errorf("No projects you are a member of contained remote URL %s", remoteUrl)
	}

	c.projectId = fmt.Sprint(project.ID)

	options := gitlab.ListProjectMergeRequestsOptions{
		Scope:        gitlab.String("all"),
		State:        gitlab.String("opened"),
		SourceBranch: &branchName,
	}

	mergeRequests, _, err := c.git.MergeRequests.ListProjectMergeRequests(c.projectId, &options)
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

var requestLogger retryablehttp.RequestLogHook = func(l retryablehttp.Logger, r *http.Request, i int) {
	file := openLogFile()
	defer file.Close()

	token := r.Header.Get("Private-Token")
	r.Header.Set("Private-Token", "REDACTED")
	res, err := httputil.DumpRequest(r, true)
	if err != nil {
		log.Fatalf("Error dumping request: %v", err)
		os.Exit(1)
	}
	r.Header.Set("Private-Token", token)

	_, err = file.Write([]byte("\n-- REQUEST --\n")) //nolint:all
	_, err = file.Write(res)                         //nolint:all
	_, err = file.Write([]byte("\n"))                //nolint:all
}

var responseLogger retryablehttp.ResponseLogHook = func(l retryablehttp.Logger, response *http.Response) {
	file := openLogFile()
	defer file.Close()

	res, err := httputil.DumpResponse(response, true)
	if err != nil {
		log.Fatalf("Error dumping response: %v", err)
		os.Exit(1)
	}

	_, err = file.Write([]byte("\n-- RESPONSE --\n")) //nolint:all
	_, err = file.Write(res)                          //nolint:all
	_, err = file.Write([]byte("\n"))                 //nolint:all
}

func openLogFile() *os.File {
	logFile := os.Args[len(os.Args)-1]
	file, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("Log file %s does not exist", logFile)
		} else if os.IsPermission(err) {
			log.Printf("Permission denied for log file %s", logFile)
		} else {
			log.Printf("Error opening log file %s: %v", logFile, err)
		}

		os.Exit(1)
	}

	return file
}
