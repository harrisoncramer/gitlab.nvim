package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

type AttachmentResponse struct {
	SuccessResponse
	Markdown string `json:"markdown"`
	Alt      string `json:"alt"`
	Url      string `json:"url"`
}

func AttachmentHandler(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo) {
	w.Header().Set("Content-Type", "application/json")
	if r.Method != http.MethodPost {
		w.Header().Set("Access-Control-Allow-Methods", http.MethodPost)
		HandleError(w, InvalidRequestError{}, "Expected POST", http.StatusMethodNotAllowed)
		return
	}

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

	file := r.Context().Value(fileReaderKey).(io.Reader)

	projectFile, res, err := c.UploadFile(d.ProjectId, file, attachmentRequest.FileName)
	if err != nil {
		HandleError(w, err, fmt.Sprintf("Could not upload %s to Gitlab", attachmentRequest.FileName), http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		HandleError(w, GenericError{endpoint: "/mr/attachment"}, fmt.Sprintf("Could not upload %s to Gitlab", attachmentRequest.FileName), res.StatusCode)
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
