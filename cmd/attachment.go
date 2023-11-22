package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"

	"github.com/xanzy/go-gitlab"
)

type AttachmentRequest struct {
	FilePath string `json:"file_path"`
	FileName string `json:"file_name"`
}

type AttachmentResponse struct {
	SuccessResponse
	Markdown string `json:"markdown"`
	Alt      string `json:"alt"`
	Url      string `json:"url"`
}

func AttachmentHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	c := r.Context().Value("client").(*gitlab.Client)
	d := r.Context().Value("data").(*ProjectInfo)

	var attachmentRequest AttachmentRequest
	body, err := io.ReadAll(r.Body)
	if err != nil {
		HandleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	err = json.Unmarshal(body, &attachmentRequest)
	if err != nil {
		HandleError(w, err, "Could not unmarshal JSON", http.StatusBadRequest)
		return
	}

	file, err := os.Open(attachmentRequest.FilePath)
	if err != nil {
		HandleError(w, err, fmt.Sprintf("Could not read %s", attachmentRequest.FilePath), http.StatusBadRequest)
		return
	}

	defer file.Close()

	projectFile, res, err := c.Projects.UploadFile(d.ProjectId, file, attachmentRequest.FileName)
	if err != nil {
		HandleError(w, err, fmt.Sprintf("Could not upload %s to Gitlab", attachmentRequest.FilePath), res.StatusCode)
		return
	}

	response := AttachmentResponse{
		SuccessResponse: SuccessResponse{
			Status:  http.StatusOK,
			Message: "File uploaded successfully",
		},
		Markdown: projectFile.Markdown,
		Alt:      projectFile.Alt,
		Url:      projectFile.URL,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		HandleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
