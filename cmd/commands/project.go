package commands

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

type Project struct {
	ID                int       `json:"id"`
	Description       string    `json:"description"`
	Name              string    `json:"name"`
	NameWithNamespace string    `json:"name_with_namespace"`
	Path              string    `json:"path"`
	PathWithNamespace string    `json:"path_with_namespace"`
	CreatedAt         time.Time `json:"created_at"`
	DefaultBranch     string    `json:"default_branch"`
	TagList           []string  `json:"tag_list"`
	Topics            []string  `json:"topics"`
	WebURL            string    `json:"web_url"`
	ReadmeURL         string    `json:"readme_url"`
	ForksCount        int       `json:"forks_count"`
	AvatarURL         string    `json:"avatar_url"`
	StarCount         int       `json:"star_count"`
	LastActivityAt    time.Time `json:"last_activity_at"`
}

/* Returns metadata about the current project */
func GetProjectInfo() Project {
	cmd := exec.Command("bash", "-c", "basename \"$(git rev-parse --show-toplevel)\" ")
	output, err := cmd.Output()

	if err != nil {
		fmt.Println("Error running git rev-parse:", err)
	}

	projectName := strings.TrimSpace(string(output))

	if err != nil {
		fmt.Println("Error getting repository name:", err)
		os.Exit(1)
	}

	url := fmt.Sprintf("https://gitlab.com/api/v4/projects?search=%s&owned=true", projectName)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Add("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))

	client := &http.Client{}
	res, err := client.Do(req)

	if err != nil {
		fmt.Println("Error getting repository info:", err)
		os.Exit(1)
	}

	if res.StatusCode != http.StatusOK {
		fmt.Println("Repo returned non-200 exit code: ", res.StatusCode)
		os.Exit(1)
	}
	defer res.Body.Close()

	body, err := io.ReadAll(res.Body)
	if err != nil {
		fmt.Println("Error reading body: ", err)
		os.Exit(1)
	}

	var project []Project
	err = json.Unmarshal(body, &project)
	if err != nil {
		fmt.Println("Error unmarshaling data from JSON: ", err)
		os.Exit(1)
	}

	if len(project) > 1 {
		fmt.Println("Please provide a unique project name")
		os.Exit(1)
	}

	if len(project) == 0 {
		fmt.Println("Project not found")
		os.Exit(1)

	}

	return project[0]

}
