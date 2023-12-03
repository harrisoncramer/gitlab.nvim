package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
)

type FileReader interface {
	ReadFile(path string) (io.Reader, error)
}

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

type attachmentReader struct{}

func (ar attachmentReader) ReadFile(path string) (io.Reader, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}

	data, err := io.ReadAll(file)
	if err != nil {
		return nil, err
	}

	defer file.Close()

	reader := bytes.NewReader(data)

	return reader, nil
}

func (a *api) attachmentHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		handleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

	var attachmentRequest AttachmentRequest

	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	err = json.Unmarshal(body, &attachmentRequest)
	if err != nil {
		handleError(w, err, "Could not unmarshal JSON", http.StatusBadRequest)
		return
	}

	file, err := a.fileReader.ReadFile(attachmentRequest.FileName)
	if err != nil {
		handleError(w, err, fmt.Sprintf("Could not read %s file", attachmentRequest.FileName), http.StatusInternalServerError)
	}

	projectFile, res, err := a.client.UploadFile(a.projectInfo.ProjectId, file, attachmentRequest.FileName)
	if err != nil {
		handleError(w, err, fmt.Sprintf("Could not upload %s to Gitlab", attachmentRequest.FileName), http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/attachment"}, fmt.Sprintf("Could not upload %s to Gitlab", attachmentRequest.FileName), res.StatusCode)
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
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
