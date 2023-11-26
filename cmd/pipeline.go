package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/xanzy/go-gitlab"
)

type RetriggerPipelineResponse struct {
	SuccessResponse
	Pipeline *gitlab.Pipeline
}

type GetJobsResponse struct {
	SuccessResponse
	Jobs []*gitlab.Job
}

func pipelineHandler(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo) {
	switch r.Method {
	case http.MethodGet:
		GetJobs(w, r, c, d)
	case http.MethodPost:
		RetriggerPipeline(w, r, c, d)
	default:
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Methods", fmt.Sprintf("%s, %s", http.MethodGet, http.MethodPost))
		handleError(w, InvalidRequestError{}, "Expected GET or POST", http.StatusMethodNotAllowed)
	}
}

func GetJobs(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")

	id := strings.TrimPrefix(r.URL.Path, "/pipeline/")
	idInt, err := strconv.Atoi(id)

	if err != nil {
		handleError(w, err, "Could not convert pipeline ID to integer", http.StatusBadRequest)
		return
	}

	jobs, res, err := c.ListPipelineJobs(d.ProjectId, idInt, &gitlab.ListJobsOptions{})

	if err != nil {
		handleError(w, err, "Could not get pipeline jobs", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/pipeline"}, "Could not get pipeline jobs", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := GetJobsResponse{
		SuccessResponse: SuccessResponse{
			Status:  http.StatusOK,
			Message: "Pipeline jobs retrieved",
		},
		Jobs: jobs,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

func RetriggerPipeline(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")

	id := strings.TrimPrefix(r.URL.Path, "/pipeline/")

	idInt, err := strconv.Atoi(id)
	if err != nil {
		handleError(w, err, "Could not convert pipeline ID to integer", http.StatusBadRequest)
		return
	}

	pipeline, res, err := c.RetryPipelineBuild(d.ProjectId, idInt)

	if err != nil {
		handleError(w, err, "Could not retrigger pipeline", res.StatusCode)
		return
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
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
