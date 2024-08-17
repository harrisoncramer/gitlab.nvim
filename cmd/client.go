package main

import (
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"os"

	"github.com/hashicorp/go-retryablehttp"
	"github.com/xanzy/go-gitlab"
)

type ProjectInfo struct {
	ProjectId string
	MergeId   int
}

/* The Client struct embeds all the methods from Gitlab for the different services */
type Client struct {
	*gitlab.MergeRequestsService
	*gitlab.MergeRequestApprovalsService
	*gitlab.DiscussionsService
	*gitlab.ProjectsService
	*gitlab.ProjectMembersService
	*gitlab.JobsService
	*gitlab.PipelinesService
	*gitlab.LabelsService
	*gitlab.AwardEmojiService
	*gitlab.UsersService
	*gitlab.DraftNotesService
}

/* initGitlabClient parses and validates the project settings and initializes the Gitlab client. */
func initGitlabClient() (error, *Client) {

	if pluginOptions.GitlabUrl == "" {
		return errors.New("GitLab instance URL cannot be empty"), nil
	}

	var apiCustUrl = fmt.Sprintf(pluginOptions.GitlabUrl + "/api/v4")

	gitlabOptions := []gitlab.ClientOptionFunc{
		gitlab.WithBaseURL(apiCustUrl),
	}

	if pluginOptions.Debug.Request {
		gitlabOptions = append(gitlabOptions, gitlab.WithRequestLogHook(requestLogger))
	}

	if pluginOptions.Debug.Response {
		gitlabOptions = append(gitlabOptions, gitlab.WithResponseLogHook(responseLogger))
	}

	tr := &http.Transport{
		TLSClientConfig: &tls.Config{
			InsecureSkipVerify: pluginOptions.Insecure,
		},
	}

	retryClient := retryablehttp.NewClient()
	retryClient.HTTPClient.Transport = tr
	gitlabOptions = append(gitlabOptions, gitlab.WithHTTPClient(retryClient.HTTPClient))

	client, err := gitlab.NewClient(pluginOptions.AuthToken, gitlabOptions...)

	if err != nil {
		return fmt.Errorf("Failed to create client: %v", err), nil
	}

	return nil, &Client{
		MergeRequestsService:         client.MergeRequests,
		MergeRequestApprovalsService: client.MergeRequestApprovals,
		DiscussionsService:           client.Discussions,
		ProjectsService:              client.Projects,
		ProjectMembersService:        client.ProjectMembers,
		JobsService:                  client.Jobs,
		PipelinesService:             client.Pipelines,
		LabelsService:                client.Labels,
		AwardEmojiService:            client.AwardEmoji,
		UsersService:                 client.Users,
		DraftNotesService:            client.DraftNotes,
	}
}

/* initProjectSettings fetch the project ID using the client */
func initProjectSettings(c *Client, gitInfo GitProjectInfo) (error, *ProjectInfo) {

	opt := gitlab.GetProjectOptions{}
	project, _, err := c.GetProject(gitInfo.projectPath(), &opt)

	if err != nil {
		return fmt.Errorf(fmt.Sprintf("Error getting project at %s", gitInfo.RemoteUrl), err), nil
	}
	if project == nil {
		return fmt.Errorf(fmt.Sprintf("Could not find project at %s", gitInfo.RemoteUrl), err), nil
	}

	projectId := fmt.Sprint(project.ID)

	return nil, &ProjectInfo{
		ProjectId: projectId,
	}

}

/* handleError is a utililty handler that returns errors to the client along with their statuses and messages */
func handleError(w http.ResponseWriter, err error, message string, status int) {
	w.WriteHeader(status)
	response := ErrorResponse{
		Message: message,
		Details: err.Error(),
		Status:  status,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode error response", http.StatusInternalServerError)
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
	file, err := os.OpenFile(pluginOptions.LogPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("Log file %s does not exist", pluginOptions.LogPath)
		} else if os.IsPermission(err) {
			log.Printf("Permission denied for log file %s", pluginOptions.LogPath)
		} else {
			log.Printf("Error opening log file %s: %v", pluginOptions.LogPath, err)
		}

		os.Exit(1)
	}

	return file
}
