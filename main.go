package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

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

const (
	projectId = 40444811
)

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

func main() {
	mergeId := getCurrentMergeId()

	/* Get MR information */
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
	createComment(mergeId, projectId, diffVersionInfo[0])

}

func createComment(mergeId string, projectId int, mrInfo MRVersion) {
	payload := &bytes.Buffer{}
	writer := multipart.NewWriter(payload)

	makeNote(mrInfo, writer, "This is some comment")

	err := writer.Close()
	if err != nil {
		log.Fatalf("Error closing writer: %v", err)
	}

	client := &http.Client{}
	url := fmt.Sprintf("https://gitlab.com/api/v4/projects/%d/merge_requests/%s/discussions", projectId, mergeId)

	req, err := http.NewRequest(http.MethodPost, url, payload)
	if err != nil {
		log.Fatalf("Error creating new request: %v", err)
	}

	req.Header.Add("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))
	req.Header.Set("Content-Type", writer.FormDataContentType())

	res, err := client.Do(req)
	if err != nil {
		log.Fatalf("Failed to post comment: %s", err)
	}

	_, err = io.ReadAll(res.Body)
	if err != nil {
		log.Fatalf("Error reading body: %v", err)
	}

	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		log.Fatalf("Recieved non-200 exit: %d", res.StatusCode)
		log.Fatalf("Error: %s", res.Body)
	}

	log.Println("Success!")
}

// func createThread(mergeId string, projectId int) {
//
// 	url := fmt.Sprintf("https://gitlab.com/api/v4/projects/%d/merge_requests/%s/discussions?body=comment", projectId, mergeId)
// 	req, err := http.NewRequest(http.MethodPost, url, nil)
// 	if err != nil {
// 		log.Fatalf("Error creating thread request: %v", err)
// 	}
//
// 	req.Header.Add("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))
//
// 	client := &http.Client{}
// 	res, err := client.Do(req)
// 	if err != nil {
// 		log.Fatalf("Error creating thread: %v", err)
// 	}
//
// 	defer res.Body.Close()
// 	if res.StatusCode != http.StatusOK {
// 		log.Fatalf("Error creating thread: %v", err)
// 	}
//
// }

/* Gets the latest merge request revision data */
func getMRVersions(mergeId string, projectId int) (e error, response *http.Response) {

	gitlabToken := os.Getenv("GITLAB_TOKEN")
	url := fmt.Sprintf("https://gitlab.com/api/v4/projects/%d/merge_requests/%s/versions", projectId, mergeId)

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

/* Makes a note on the MR */
func makeNote(version MRVersion, w *multipart.Writer, comment string) error {
	payload := &bytes.Buffer{}

	writer := multipart.NewWriter(payload) /* Creates a new multipart writer, which is a MIME type with multiple parts */
	_ = writer.WriteField("position[position_type]", "text")
	_ = writer.WriteField("position[base_sha]", version.BaseCommitSHA)
	_ = writer.WriteField("position[head_sha]", version.HeadCommitSHA)
	_ = writer.WriteField("position[start_sha]", version.StartCommitSHA)
	_ = writer.WriteField("position[new_path]", "New_file.txt")
	_ = writer.WriteField("position[old_path]", "New_file.txt")
	_ = writer.WriteField("position[new_line]", "1")
	_ = writer.WriteField("body", comment)

	return nil
}
