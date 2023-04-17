package commands

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

const commentsUrl = "https://gitlab.com/api/v4/projects/%s/merge_requests/%s/notes?sort=asc&order_by=updated_at"

type MergeRequestNote struct {
	ID              int                    `json:"id"`
	Type            interface{}            `json:"type"`
	Body            string                 `json:"body"`
	Attachment      interface{}            `json:"attachment"`
	Author          Author                 `json:"author"`
	CreatedAt       time.Time              `json:"created_at"`
	UpdatedAt       time.Time              `json:"updated_at"`
	System          bool                   `json:"system"`
	NoteableID      int                    `json:"noteable_id"`
	NoteableType    string                 `json:"noteable_type"`
	ProjectID       int                    `json:"project_id"`
	Resolvable      bool                   `json:"resolvable"`
	Confidential    bool                   `json:"confidential"`
	Internal        bool                   `json:"internal"`
	NoteableIID     int                    `json:"noteable_iid"`
	CommandsChanges map[string]interface{} `json:"commands_changes"`
}

type Author struct {
	ID        int    `json:"id"`
	Username  string `json:"username"`
	Name      string `json:"name"`
	State     string `json:"state"`
	AvatarURL string `json:"avatar_url"`
	WebURL    string `json:"web_url"`
}

func ListComments(projectId string) {
	mergeId := getCurrentMergeId()

	url := fmt.Sprintf(commentsUrl, projectId, mergeId)

	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		log.Fatalf("Error building request: %s", err)
	}

	req.Header.Set("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))

	res, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Fatalf("Error getting comments: %s", err)
	}

	defer res.Body.Close()
	body, err := io.ReadAll(res.Body)
	if err != nil {
		log.Fatalf("Error reading comments body: %s", err)
	}

	var notes []MergeRequestNote
	err = json.Unmarshal(body, &notes)
	if err != nil {
		log.Fatalf("Could not unmarshal comments data: %s", err)
	}

	var comments []MergeRequestNote
	for i := 0; i < len(notes); i++ {
		note := notes[i]
		if note.Type == "DiffNote" {
			comments = append(comments, note)
		}
	}

	output, err := json.Marshal(comments)
	if err != nil {
		log.Fatalf("Could not re-marshal comment data: %s", err)
	}

	fmt.Println(string(output))

}
