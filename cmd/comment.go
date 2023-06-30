package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"mime/multipart"
	"net/http"
	"time"

	"github.com/xanzy/go-gitlab"
)

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

type PostCommentRequest struct {
	LineNumber int    `json:"line_number"`
	FileName   string `json:"file_name"`
	Comment    string `json:"comment"`
}

type DeleteCommentRequest struct {
	NoteId       int    `json:"note_id"`
	DiscussionId string `json:"discussion_id"`
}

type EditCommentRequest struct {
	Comment      string `json:"comment"`
	NoteId       int    `json:"note_id"`
	DiscussionId string `json:"discussion_id"`
}

func CommentHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodDelete:
		DeleteComment(w, r)
	case http.MethodPost:
		PostComment(w, r)
	case http.MethodPatch:
		EditComment(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func DeleteComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		errMsg := map[string]string{"message": "Could not read request body"}
		jsonMsg, _ := json.Marshal(errMsg)
		w.Write(jsonMsg)
		return
	}

	defer r.Body.Close()

	var deleteCommentRequest DeleteCommentRequest
	err = json.Unmarshal(body, &deleteCommentRequest)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		errMsg := map[string]string{"message": "Could not read JSON from request"}
		jsonMsg, _ := json.Marshal(errMsg)
		w.Write(jsonMsg)
		return
	}

	res, err := c.git.Discussions.DeleteMergeRequestDiscussionNote(c.projectId, c.mergeId, deleteCommentRequest.DiscussionId, deleteCommentRequest.NoteId)

	w.WriteHeader(res.Response.StatusCode)

	if err != nil {
		response := ErrorResponse{
			Message: err.Error(),
			Status:  res.Response.StatusCode,
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	response := SuccessResponse{
		Message: "Comment deleted succesfully",
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)
}

func PostComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		errMsg := map[string]string{"message": "Could not read request body"}
		jsonMsg, _ := json.Marshal(errMsg)
		w.Write(jsonMsg)
		return
	}

	defer r.Body.Close()

	var postCommentRequest PostCommentRequest
	err = json.Unmarshal(body, &postCommentRequest)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		errMsg := map[string]string{"message": "Could not unmarshal data from request body"}
		jsonMsg, _ := json.Marshal(errMsg)
		w.Write(jsonMsg)
		return
	}

	res, err := c.PostComment(postCommentRequest)
	for k, v := range res.Header {
		w.Header().Set(k, v[0])
	}

	if err != nil {
		response := ErrorResponse{
			Message: err.Error(),
			Status:  res.StatusCode,
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	response := SuccessResponse{
		Message: "Comment created succesfully",
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)

	// w.WriteHeader(res.StatusCode)
	// io.Copy(w, res.Body)

}

func EditComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	body, err := io.ReadAll(r.Body)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		errMsg := map[string]string{"message": "Could not read request body"}
		jsonMsg, _ := json.Marshal(errMsg)
		w.Write(jsonMsg)
		return
	}

	defer r.Body.Close()

	var editCommentRequest EditCommentRequest
	err = json.Unmarshal(body, &editCommentRequest)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		errMsg := map[string]string{"message": "Could not unmarshal data from request body"}
		jsonMsg, _ := json.Marshal(errMsg)
		w.Write(jsonMsg)
		return
	}

	options := gitlab.UpdateMergeRequestDiscussionNoteOptions{
		Body: gitlab.String(editCommentRequest.Comment),
	}

	_, res, err := c.git.Discussions.UpdateMergeRequestDiscussionNote(c.projectId, c.mergeId, editCommentRequest.DiscussionId, editCommentRequest.NoteId, &options)

	for k, v := range res.Header {
		w.Header().Set(k, v[0])
	}

	if err != nil {
		response := ErrorResponse{
			Message: err.Error(),
			Status:  res.StatusCode,
		}
		json.NewEncoder(w).Encode(response)
		return
	}

	response := SuccessResponse{
		Message: "Comment edited succesfully",
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)
}

func (c *Client) PostComment(cr PostCommentRequest) (*http.Response, error) {

	err, response := getMRVersions(c.gitlabInstance, c.projectId, c.mergeId, c.authToken)
	if err != nil {
		return nil, fmt.Errorf("Error making diff thread: %e", err)
	}

	defer response.Body.Close()

	body, err := ioutil.ReadAll(response.Body)

	var diffVersionInfo []MRVersion
	err = json.Unmarshal(body, &diffVersionInfo)
	if err != nil {
		return nil, fmt.Errorf("Error unmarshalling version info JSON: %w", err)
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
		res, err := c.CommentOnDeletion(cr.LineNumber, cr.FileName, cr.Comment, diffVersionInfo[0], ii)

		if err == nil && res.StatusCode >= 200 && res.StatusCode <= 299 {
			return res, nil
		}
	}

	return nil, fmt.Errorf("Could not leave comment")

}

func min(a int, b int) int {
	if a < b {
		return a
	}
	return b
}

/* Gets the latest merge request revision data */
func getMRVersions(gitlabInstance string, projectId string, mergeId int, authToken string) (e error, response *http.Response) {
	const mrVersionsUrl = "%s/api/v4/projects/%s/merge_requests/%d/versions"
	url := fmt.Sprintf(gitlabInstance, mrVersionsUrl, projectId, mergeId)

	req, err := http.NewRequest(http.MethodGet, url, nil)

	req.Header.Add("PRIVATE-TOKEN", authToken)

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
func (c *Client) CommentOnDeletion(lineNumber int, fileName string, comment string, diffVersionInfo MRVersion, i int) (*http.Response, error) {

	deletionDiscussionUrl := fmt.Sprintf(c.gitlabInstance+"/api/v4/projects/%s/merge_requests/%d/discussions", c.projectId, c.mergeId)

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
		_ = writer.WriteField("position[old_line]", fmt.Sprintf("%d", lineNumber))
	} else if i == 1 {
		_ = writer.WriteField("position[new_line]", fmt.Sprintf("%d", lineNumber))
	} else {
		_ = writer.WriteField("position[old_line]", fmt.Sprintf("%d", lineNumber))
		_ = writer.WriteField("position[new_line]", fmt.Sprintf("%d", lineNumber))
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
	req.Header.Add("PRIVATE-TOKEN", c.authToken)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	res, err := client.Do(req)

	return res, err
}
