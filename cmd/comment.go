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
	"strings"
	"sync"
	"time"

	"github.com/xanzy/go-gitlab"
)

const mrVersionsUrl = "https://gitlab.com/api/v4/projects/%s/merge_requests/%d/versions"
const commentUrl = "https://gitlab.com/api/v4/projects/%s/repository/commits/%s/comments"

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
	if len(os.Args) < 7 {
		c.Usage("comment")
	}

	lineNumber, fileName, comment, sha := os.Args[3], os.Args[4], os.Args[5], os.Args[6]
	if lineNumber == "" || fileName == "" || comment == "" {
		c.Usage("comment")
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
	if err != nil {
		return fmt.Errorf("Error unmarshalling version info JSON: %w", err)
	}

	time := time.Now()

	if sha == "" {
		/* This is necessary since we do not know whether the comment is on a line that
		has been changed or not. Making all three of these API calls will let us leave
		the comment regardless. See the Gitlab documentation: https://docs.gitlab.com/ee/api/discussions.html#create-a-new-thread-in-the-merge-request-diff */
		wg := sync.WaitGroup{}
		wg.Add(2)

		resultChannel := make(chan *gitlab.Discussion, 2)

		for i := 0; i < 2; i++ {
			ii := i
			go func() {
				defer wg.Done()
				options := gitlab.CreateMergeRequestDiscussionOptions{
					Body:      &comment,
					CreatedAt: &time,
					Position: &gitlab.NotePosition{
						PositionType: "text",
						BaseSHA:      diffVersionInfo[0].BaseCommitSHA,
						HeadSHA:      diffVersionInfo[0].HeadCommitSHA,
						StartSHA:     diffVersionInfo[0].StartCommitSHA,
						NewPath:      fileName,
						OldPath:      fileName,
					},
				}

				if ii == 0 {
					options.Position.NewLine = lineNumberInt
				} else {
					options.Position.NewLine = lineNumberInt
					options.Position.OldLine = lineNumberInt
				}

				discussion, _, _ := c.git.Discussions.CreateMergeRequestDiscussion(c.projectId, c.mergeId, &options)
				resultChannel <- discussion

			}()
		}

		go func() {
			wg.Wait()
			close(resultChannel)
		}()

		var createdDiscussion *gitlab.Discussion
		for discussion := range resultChannel {
			if discussion != nil {
				createdDiscussion = discussion
			}
		}

		if createdDiscussion == nil {
			return fmt.Errorf("Could not leave comment")
		}
	} else {
		payload := &bytes.Buffer{}
		writer := multipart.NewWriter(payload)
		_ = writer.WriteField("note", comment)
		_ = writer.WriteField("path", "README.md")
		_ = writer.WriteField("line", "3")
		_ = writer.WriteField("line_type", "old")
		err := writer.Close()
		if err != nil {
			return fmt.Errorf("Error making form data: %w", err)
		}

		url := fmt.Sprintf(commentUrl, c.projectId, strings.TrimSpace(sha))
		client := &http.Client{}
		req, err := http.NewRequest(http.MethodPost, url, payload)

		if err != nil {
			return fmt.Errorf("Error building request: %w", err)
		}

		req.Header.Add("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))
		req.Header.Set("Content-Type", writer.FormDataContentType())

		res, err := client.Do(req)
		if err != nil {
			return fmt.Errorf("Error making request: %w", err)
		}
		defer res.Body.Close()
	}

	fmt.Println("Left Comment: " + comment[0:min(len(comment), 25)] + "...")
	return nil
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
