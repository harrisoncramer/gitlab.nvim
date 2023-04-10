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
	"os/exec"
	"strings"
	"time"
)

const (
	projectId      = 40444811
	discussionsUrl = "https://gitlab.com/api/v4/projects/%d/merge_requests/%s/discussions"
	mrVersionsUrl  = "https://gitlab.com/api/v4/projects/%d/merge_requests/%s/versions"
)

type Comment struct {
	View                    string `json:"view"`
	LineType                string `json:"line_type"`
	MergeRequestDiffHeadSha string `json:"merge_request_diff_head_sha"`
	InReplyToDiscussionId   string `json:"in_reply_to_discussion_id"`
	NoteProjectId           string `json:"note_project_id"`
	TargetType              string `json:"target_type"`
	TargetId                int    `json:"target_id"`
	ReturnDiscussion        bool   `json:"return_discussion"`
	Note                    struct {
		Note         string `json:"note"`
		Position     string `json:"position"`
		NoteableType string `json:"noteable_type"`
		NoteableId   int    `json:"noteable_id"`
		CommitId     int    `json:"commit_id"`
		Type         string `json:"type"`
		LineCode     string `json:"line_code"`
	}
}

type Position struct {
	BaseSha      string    `json:"base_sha"`
	StartSha     string    `json:"start_sha"`
	HeadSha      string    `json:"head_sha"`
	OldPath      string    `json:"old_path"`
	NewPath      string    `json:"new_path"`
	PositionType string    `json:"position_type"`
	OldLine      *string   `json:"old_line"`
	NewLine      int       `json:"new_line"`
	LineRange    LineRange `json:"line_range"`
}

type LineRange struct {
	Start LineInfo `json:"start"`
	End   LineInfo `json:"end"`
}

type LineInfo struct {
	LineCode string  `json:"line_code"`
	Type     string  `json:"type"`
	OldLine  *string `json:"old_line"`
	NewLine  int     `json:"new_line"`
}

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

func main() {
	mergeId := getCurrentMergeId()

	err, response := getMRVersions(mergeId, projectId)
	if err != nil {
		log.Fatalf("Error making diff thread: %err", err)
	}
	defer response.Body.Close()

	body, err := ioutil.ReadAll(response.Body)

	var diffVersionInfo []MRVersion
	err = json.Unmarshal(body, &diffVersionInfo)

	if err != nil {
		log.Fatalf("Could not unmarshal data: %v", err)
	}

	/* Create a thread for discussion with latest MR information */
	err = createComment(mergeId, projectId, diffVersionInfo[0])
	if err != nil {
		log.Fatalf("Error making comment thread: %v", err)
	}

	log.Println("Comment created!")

}

/* POSTs the comment to the merge request */
func createComment(mergeId string, projectId int, mrInfo MRVersion) error {

	payload := &bytes.Buffer{}
	writer := multipart.NewWriter(payload)
	_ = writer.WriteField("position[position_type]", "text")
	_ = writer.WriteField("position[base_sha]", mrInfo.BaseCommitSHA)
	_ = writer.WriteField("position[head_sha]", mrInfo.HeadCommitSHA)
	_ = writer.WriteField("position[start_sha]", mrInfo.StartCommitSHA)
	_ = writer.WriteField("position[new_path]", "main.go")
	_ = writer.WriteField("position[old_path]", "main.go")
	_ = writer.WriteField("position[new_line]", "119")
	_ = writer.WriteField("body", "Another new comment!")
	err := writer.Close()
	if err != nil {
		return err
	}

	client := &http.Client{}
	req, err := http.NewRequest(http.MethodPost, fmt.Sprintf(discussionsUrl, projectId, mergeId), payload)

	if err != nil {
		return err
	}
	req.Header.Add("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))

	req.Header.Set("Content-Type", writer.FormDataContentType())
	res, err := client.Do(req)
	if err != nil {
		return err
	}

	if res.StatusCode != http.StatusOK {
		return err
	}
	defer res.Body.Close()

	return nil
}

/* Gets the latest merge request revision data */
func getMRVersions(mergeId string, projectId int) (e error, response *http.Response) {

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

/* Gets the current merge request ID from local Git */
func getCurrentMergeId() string {
	gitCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")

	output, err := gitCmd.Output()
	if err != nil {
		fmt.Println("Error running git rev-parse:", err)
		os.Exit(1)
	}

	sourceBranch := strings.TrimSpace(string(output))

	glabCmd := exec.Command("bash", "-c", `glab mr list --source-branch=`+sourceBranch+` | cat | head -n3 | tail -n 1 | awk '{print $1}' | cut -c 2`)

	output, err = glabCmd.Output()
	if err != nil {
		fmt.Println("Error running the command:", err)
		os.Exit(1)
	}

	result := strings.TrimSpace(string(output))

	return result

}
