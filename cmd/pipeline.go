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
	LatestPipeline *gitlab.Pipeline `json:"latest_pipeline"`
}

type PipelineWithJobs struct {
	Jobs           []*gitlab.Job    `json:"jobs"`
	LatestPipeline *gitlab.Pipeline `json:"latest_pipeline"`
}

type GetPipelineAndJobsResponse struct {
	SuccessResponse
	Pipeline PipelineWithJobs `json:"latest_pipeline"`
}

/*
pipelineHandler fetches information about the current pipeline, and retriggers a pipeline run. For more detailed information
about a given job in a pipeline, see the jobHandler function
*/
func (a *api) pipelineHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.GetPipelineAndJobs(w, r)
	case http.MethodPost:
		a.RetriggerPipeline(w, r)
	default:
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Methods", fmt.Sprintf("%s, %s", http.MethodGet, http.MethodPost))
		handleError(w, InvalidRequestError{}, "Expected GET or POST", http.StatusMethodNotAllowed)
	}
}

func (a *api) GetPipelineAndJobs(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	pipeline, res, err := a.client.GetLatestPipeline(a.projectInfo.ProjectId, &gitlab.GetLatestPipelineOptions{
		Ref: &a.gitInfo.BranchName,
	})

	if err != nil {
		handleError(w, err, "Could not get latest pipeline", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/pipeline"}, "Could not get latest pipeline", res.StatusCode)
		return
	}

	jobs, res, err := a.client.ListPipelineJobs(a.projectInfo.ProjectId, pipeline.ID, &gitlab.ListJobsOptions{})

	if err != nil {
		handleError(w, err, "Could not get pipeline jobs", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/pipeline"}, "Could not get pipeline jobs", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := GetPipelineAndJobsResponse{
		SuccessResponse: SuccessResponse{
			Status:  http.StatusOK,
			Message: "Pipeline retrieved",
		},
		Pipeline: PipelineWithJobs{
			LatestPipeline: pipeline,
			Jobs:           jobs,
		},
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

func (a *api) RetriggerPipeline(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	id := strings.TrimPrefix(r.URL.Path, "/pipeline/trigger/")

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
		LatestPipeline: pipeline,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
