package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"mime/multipart"
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
		c.Usage("comment")
	}

	lineNumber, fileName, comment := os.Args[3], os.Args[4], os.Args[5]
	if lineNumber == "" || fileName == "" || comment == "" {
		c.Usage("comment")
	}

	err, response := getMRVersions(c.projectId, c.mergeId)
	if err != nil {
		log.Fatalf("Error making diff thread: %s", err)
	}
	defer response.Body.Close()

	body, err := ioutil.ReadAll(response.Body)

	var diffVersionInfo []MRVersion
	err = json.Unmarshal(body, &diffVersionInfo)
	if err != nil {
		return fmt.Errorf("Error unmarshalling version info JSON: %w", err)
	}

	/* This is necessary since we do not know whether the comment is on a line that
	   has been changed or not. Making all three of these API calls will let us leave
	   the comment regardless. I ran these in sequence vai a Sync.WaitGroup, but
	   it was successfully posting a comment to a modified twice, so now I'm running
	   them in sequence.

	   To clean this up we might try to detect more information about the change in our
	   Lua code and pass it to the Go code.

	   See the Gitlab documentation: https://docs.gitlab.com/ee/api/discussions.html#create-a-new-thread-in-the-merge-request-diff */
	for i := 0; i < 3; i++ {
		ii := i
		_, err := c.CommentOnDeletion(lineNumber, fileName, comment, diffVersionInfo[0], ii)
		if err == nil {
			fmt.Println("Left Comment: " + comment[0:min(len(comment), 25)] + "...")
			return nil
		}
	}

	return fmt.Errorf("Could not leave comment")

}

func min(a int, b int) int {
	if a < b {
		return a
	}
	return b
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

/*
Creates a new merge request discussion https://docs.gitlab.com/ee/api/discussions.html#create-new-merge-request-thread
The go-gitlab client was not working for this API specifically 😢
*/
func (c *Client) CommentOnDeletion(lineNumber string, fileName string, comment string, diffVersionInfo MRVersion, i int) (*http.Response, error) {

	deletionDiscussionUrl := fmt.Sprintf("https://gitlab.com/api/v4/projects/%s/merge_requests/%d/discussions", c.projectId, c.mergeId)

	payload := &bytes.Buffer{}
	writer := multipart.NewWriter(payload)
	_ = writer.WriteField("body", comment)
	_ = writer.WriteField("position[base_sha]", diffVersionInfo.BaseCommitSHA)
	_ = writer.WriteField("position[start_sha]", diffVersionInfo.StartCommitSHA)
	_ = writer.WriteField("position[head_sha]", diffVersionInfo.HeadCommitSHA)
	_ = writer.WriteField("position[position_type]", "text")

	/* We need to set these properties differently depending on whether we're commenting on a deleted line,
	a modified line, an added line, or an unmodified line */
	_ = writer.WriteField("position[old_path]", fileName)
	_ = writer.WriteField("position[new_path]", fileName)
	if i == 0 {
		_ = writer.WriteField("position[old_line]", lineNumber)
	} else if i == 1 {
		_ = writer.WriteField("position[new_line]", lineNumber)
	} else {
		_ = writer.WriteField("position[old_line]", lineNumber)
		_ = writer.WriteField("position[new_line]", lineNumber)
	}

	err := writer.Close()
	if err != nil {
		return nil, fmt.Errorf("Error making form data: %w", err)
	}

	client := &http.Client{}
	req, err := http.NewRequest(http.MethodPost, deletionDiscussionUrl, payload)

	if err != nil {
		return nil, fmt.Errorf("Error building request: %w", err)
	}
	req.Header.Add("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))

	req.Header.Set("Content-Type", writer.FormDataContentType())
	res, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Error making request: %w", err)
	}

	defer res.Body.Close()
	return res, nil
}

func (c *Client) OverviewComment() error {
	lineNumber, fileName, comment, sha := os.Args[3], os.Args[4], os.Args[5], os.Args[6]
	if lineNumber == "" || fileName == "" || comment == "" {
		c.Usage("comment")
	}

	lineNumberInt, err := strconv.Atoi(lineNumber)
	if err != nil {
		return fmt.Errorf("Not a valid line number: %w", err)
	}

	postCommitCommentOptions := gitlab.PostCommitCommentOptions{
		Note:     gitlab.String(comment),
		Path:     gitlab.String(fileName),
		Line:     &lineNumberInt,
		LineType: gitlab.String("old"),
	}
	_, _, err = c.git.Commits.PostCommitComment(c.projectId, sha, &postCommitCommentOptions)
	if err != nil {
		return fmt.Errorf("Error leaving overview comment: %w", err)
	}

	fmt.Println("Left Overview Comment: " + comment[0:min(len(comment), 25)] + "...")
	return nil
}
