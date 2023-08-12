package main

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type UpdateRequest struct {
	Description string `json:"description"`
}

func UpdateHandler(w http.ResponseWriter, r *http.Request) {
	c := r.Context().Value("client").(Client)
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPut {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()
	var updateRequest UpdateRequest
	err = json.Unmarshal(body, &updateRequest)

	if err != nil {
		c.handleError(w, err, "Could not read JSON from request", http.StatusBadRequest)
		return
	}

	/* TODO: The go-gitlab library really doesn't like setting a custom base URL
	   with this PUT call, for some reason it breaks redirects. This API call
	   will fail for anyone with a self-hosted Gitlab instance, see this issue
	   on the go-gitlab library: https://github.com/xanzy/go-gitlab/issues/1771 😢 */
	git, err := gitlab.NewClient(c.authToken)
	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}

	_, res, err := git.MergeRequests.UpdateMergeRequest(c.projectId, c.mergeId, &gitlab.UpdateMergeRequestOptions{Description: &updateRequest.Description})

	if err != nil {
		c.handleError(w, err, "Could not edit merge request", http.StatusBadRequest)
		return
	}

	if res.StatusCode != http.StatusOK {
		c.handleError(w, err, "Could not edit merge request", http.StatusBadRequest)
		return
	}

	w.WriteHeader(http.StatusOK)

	response := SuccessResponse{
		Message: "Merge request updated",
		Status:  http.StatusOK,
	}

	json.NewEncoder(w).Encode(response)

}
