package main

import (
	"encoding/json"
	"io"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

type PipelineRequest struct {
	PipelineId int `json:"pipeline_id"`
}

type RetriggerPipelineResponse struct {
	SuccessResponse
	Pipeline *gitlab.Pipeline
}

type GetJobsResponse struct {
	SuccessResponse
	Jobs []*gitlab.Job
}

func PipelineHandler(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo) {
	switch r.Method {
	case http.MethodGet:
		GetJobs(w, r, c, d)
	case http.MethodPost:
		RetriggerPipeline(w, r, c, d)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func GetJobs(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")

	body, err := io.ReadAll(r.Body)
	if err != nil {
		HandleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var pipelineRequest PipelineRequest
	err = json.Unmarshal(body, &pipelineRequest)
	if err != nil {
		HandleError(w, err, "Could not read JSON", http.StatusBadRequest)
	}

	jobs, res, err := c.ListPipelineJobs(d.ProjectId, pipelineRequest.PipelineId, &gitlab.ListJobsOptions{})

	if err != nil {
		HandleError(w, err, "Could not get pipeline jobs", res.StatusCode)
	}

	w.WriteHeader(http.StatusOK)

	response := GetJobsResponse{
		SuccessResponse: SuccessResponse{
			Status:  http.StatusOK,
			Message: "Jobs fetched successfully",
		},
		Jobs: jobs,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}

}

func RetriggerPipeline(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")

	body, err := io.ReadAll(r.Body)
	if err != nil {
		HandleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var pipelineRequest PipelineRequest
	err = json.Unmarshal(body, &pipelineRequest)
	if err != nil {
		HandleError(w, err, "Could not read JSON", http.StatusBadRequest)
	}

	pipeline, res, err := c.RetryPipelineBuild(d.ProjectId, pipelineRequest.PipelineId)

	if err != nil {
		HandleError(w, err, "Could not retrigger pipeline", res.StatusCode)
	}

	w.WriteHeader(http.StatusOK)
	response := RetriggerPipelineResponse{
		SuccessResponse: SuccessResponse{
			Message: "Pipeline retriggered",
			Status:  http.StatusOK,
		},
		Pipeline: pipeline,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
