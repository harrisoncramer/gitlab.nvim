package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
)

type ImageRequest struct {
	FilePath string `json:"file_path"`
}

type ImageResponse struct {
	SuccessResponse
	Markdown string `json:"markdown"`
	Alt      string `json:"alt"`
	Url      string `json:"url"`
}

func ImageHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}

	c := r.Context().Value("Client").(Client)
	w.Header().Set("Content-Type", "application/json")

	var imageRequest ImageRequest
	body, err := io.ReadAll(r.Body)
	if err != nil {
		c.handleError(w, err, "Could not read request body", http.StatusBadRequest)
	}

	defer r.Body.Close()

	err = json.Unmarshal(body, &imageRequest)
	if err != nil {
		c.handleError(w, err, "Could not unmarshal JSON", http.StatusBadRequest)
	}

	file, err := os.Open(imageRequest.FilePath)
	if err != nil {
		c.handleError(w, err, fmt.Sprintf("Could not read %s", imageRequest.FilePath), http.StatusBadRequest)
	}

	defer file.Close()

	projectFile, res, err := c.git.Projects.UploadFile(c.projectId, file, "test")
	if err != nil {
		c.handleError(w, err, fmt.Sprintf("Could not upload %s to Gitlab", imageRequest.FilePath), res.StatusCode)
	}

	fileResponse := ImageResponse{
		SuccessResponse: SuccessResponse{
			Status:  http.StatusOK,
			Message: "File uploaded successfully",
		},
		Markdown: projectFile.Markdown,
		Alt:      projectFile.Alt,
		Url:      projectFile.URL,
	}

	json.NewEncoder(w).Encode(fileResponse)
}
