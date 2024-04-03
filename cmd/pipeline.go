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

/*
pipelineHandler fetches information about the current pipeline, and retriggers a pipeline run. For more detailed information
about a given job in a pipeline, see the jobHandler function
*/
func (a *api) pipelineHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.GetJobs(w, r)
	case http.MethodPost:
		a.RetriggerPipeline(w, r)
	default:
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Methods", fmt.Sprintf("%s, %s", http.MethodGet, http.MethodPost))
		handleError(w, InvalidRequestError{}, "Expected GET or POST", http.StatusMethodNotAllowed)
	}
}

func reverseJobs(jobs []*gitlab.Job) []*gitlab.Job {
	for i, j := 0, len(jobs)-1; i < j; i, j = i+1, j-1 {
		jobs[i], jobs[j] = jobs[j], jobs[i]
	}

	return jobs
}

func (a *api) GetJobs(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	id := strings.TrimPrefix(r.URL.Path, "/pipeline/")
	idInt, err := strconv.Atoi(id)

	if err != nil {
		handleError(w, err, "Could not convert pipeline ID to integer", http.StatusBadRequest)
		return
	}

	jobs, res, err := a.client.ListPipelineJobs(a.projectInfo.ProjectId, idInt, &gitlab.ListJobsOptions{})

	/* The jobs are by default in date ascending order, we want the opposite */
	reverseJobs(jobs)

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

func (a *api) RetriggerPipeline(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	id := strings.TrimPrefix(r.URL.Path, "/pipeline/")

	idInt, err := strconv.Atoi(id)
	if err != nil {
		handleError(w, err, "Could not convert pipeline ID to integer", http.StatusBadRequest)
		return
	}

	pipeline, res, err := a.client.RetryPipelineBuild(a.projectInfo.ProjectId, idInt)

	if err != nil {
		handleError(w, err, "Could not retrigger pipeline", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/pipeline"}, "Could not retrigger pipeline", res.StatusCode)
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
