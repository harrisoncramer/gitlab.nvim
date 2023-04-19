package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/xanzy/go-gitlab"
)

const mrVersionsUrl = "https://gitlab.com/api/v4/projects/%s/merge_requests/%d/versions"

type MRVersion struct {
	ID             int       `json:"id"`
	HeadCommitSHA  string    `json:"head_commit_sha"`
	BaseCommitSHA  string    `json:"base_commit_sha"`
	StartCommitSHA string    `json:"start_commit_sha"`
	CreatedAt      time.Time `json:"created_at"`
	MergeRequestID int       `json:"merge_request_id"`
	State          string    `json:"state"`
	RealSize       string    `json:"real_size"`
}

func (c *Client) Comment() error {
	if len(os.Args) < 6 {
		c.Usage()
	}

	lineNumber, fileName, comment := os.Args[3], os.Args[4], os.Args[5]
	if lineNumber == "" || fileName == "" || comment == "" {
		c.Usage()
	}

	lineNumberInt, err := strconv.Atoi(lineNumber)
	if err != nil {
		return fmt.Errorf("Not a valid line number: %w", err)
	}

	err, response := getMRVersions(c.projectId, c.mergeId)
	if err != nil {
		log.Fatalf("Error making diff thread: %s", err)
	}
	defer response.Body.Close()

	body, err := ioutil.ReadAll(response.Body)

	var diffVersionInfo []MRVersion
	err = json.Unmarshal(body, &diffVersionInfo)

	time := time.Now()
	options := gitlab.CreateMergeRequestDiscussionOptions{
		Body:      &comment,
		CreatedAt: &time,
		Position: &gitlab.NotePosition{
			BaseSHA: diffVersionInfo[0].BaseCommitSHA,
			HeadSHA: diffVersionInfo[0].HeadCommitSHA,
			NewPath: fileName,
			NewLine: lineNumberInt,
		},
	}

	_, _, err = c.git.Discussions.CreateMergeRequestDiscussion(c.projectId, c.mergeId, &options)

	if err != nil {
		return fmt.Errorf("Could not leave comment: %w", err)
	}

	fmt.Println("Left Comment: " + comment[0:25] + "...")

	return nil
}

/* Gets the latest merge request revision data */
func getMRVersions(projectId string, mergeId int) (e error, response *http.Response) {

	gitlabToken := os.Getenv("GITLAB_TOKEN")
	url := fmt.Sprintf(mrVersionsUrl, projectId, mergeId)

	req, err := http.NewRequest(http.MethodGet, url, nil)

	req.Header.Add("PRIVATE-TOKEN", gitlabToken)

	if err != nil {
		return err, nil
	}

	client := &http.Client{}
	response, err = client.Do(req)

	if err != nil {
		return err, nil
	}

	if response.StatusCode != 200 {
		return errors.New("Non-200 status code: " + response.Status), nil
	}

	return nil, response
}
