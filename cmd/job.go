package main

import (
	"encoding/json"
	"io"
	"net/http"
)

type JobTraceRequest struct {
	JobId int `json:"job_id"`
}

type JobTraceResponse struct {
	SuccessResponse
	File string `json:"file"`
}

func jobHandler(w http.ResponseWriter, r *http.Request, c ClientInterface, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodGet {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodGet)
		handleError(w, InvalidRequestError{}, "Expected GET", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
	}

	defer r.Body.Close()

	var jobTraceRequest JobTraceRequest
	err = json.Unmarshal(body, &jobTraceRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal data from request body", http.StatusBadRequest)
	}

	reader, _, err := c.GetTraceFile(d.ProjectId, jobTraceRequest.JobId)
	if err != nil {
		handleError(w, err, "Could not get trace file for job", http.StatusBadRequest)
	}

	file, err := io.ReadAll(reader)

	if err != nil {
		handleError(w, err, "Could not read job trace file", http.StatusBadRequest)
	}

	response := JobTraceResponse{
		SuccessResponse: SuccessResponse{
			Status:  http.StatusOK,
			Message: "Log file read",
		},
		File: string(file),
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
