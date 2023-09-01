package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type PipelineRequest struct {
	PipelineId int `json:"pipeline_id"`
}

type PipelineResponse struct {
	SuccessResponse
	Pipeline *gitlab.Pipeline
}

func PipelineHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(Client)

	if r.Method != http.MethodPost {
		c.handleError(w, errors.New("Invalid request type"), "That request type is not allowed", http.StatusMethodNotAllowed)
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	var pipelineRequest PipelineRequest
	err = json.Unmarshal(body, &pipelineRequest)
	if err != nil {
		c.handleError(w, err, "Could not read JSON", http.StatusBadRequest)
	}

	pipeline, res, err := c.git.Pipelines.RetryPipelineBuild(c.projectId, pipelineRequest.PipelineId)

	if err != nil {
		c.handleError(w, err, "Could not retrigger pipeline", res.StatusCode)
	}

	w.WriteHeader(http.StatusOK)
	response := PipelineResponse{
		SuccessResponse: SuccessResponse{
			Message: "Pipeline retriggered",
			Status:  http.StatusOK,
		},
		Pipeline: pipeline,
	}

	json.NewEncoder(w).Encode(response)

}
