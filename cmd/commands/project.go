package commands

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
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

	cmd := exec.Command("bash", "-c", "git remote get-url origin | grep 'gitlab'")
	output, err := cmd.Output()

	if err != nil {
		return Project{}
	}

	cmd = exec.Command("bash", "-c", "basename \"$(git rev-parse --show-toplevel)\" ")
	output, err = cmd.Output()

	if err != nil {
		fmt.Println("Error running git rev-parse:", err)
	}

	projectName := strings.TrimSpace(string(output))

	if err != nil {
		log.Fatalf("Error getting repository name: %s", err)
	}

	url := fmt.Sprintf("https://gitlab.com/api/v4/projects?search=%s&owned=true", projectName)
	req, err := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Add("PRIVATE-TOKEN", os.Getenv("GITLAB_TOKEN"))

	client := &http.Client{}
	res, err := client.Do(req)

	if err != nil {
		log.Fatalf("Error getting repository info: %s", err)
	}

	if res.StatusCode != http.StatusOK {
		log.Fatalf("Repo returned non-200 exit code: %d", res.StatusCode)
	}
	defer res.Body.Close()

	body, err := io.ReadAll(res.Body)
	if err != nil {
		log.Fatalf("Error reading body: %s", err)
	}

	var project []Project
	err = json.Unmarshal(body, &project)
	if err != nil {
		log.Fatalf("Error unmarshaling data from JSON: %s", err)
	}

	if len(project) > 1 {
		log.Fatal("Please provide a unique project name")
	}

	if len(project) == 0 {
		log.Fatal("Project not found")

	}

	/* We will parse this in our Lua code */
	fmt.Println(string(body))
	return project[0]

}
