package commands

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
)

const revokeUrl = "https://gitlab.com/api/v4/projects/%s/merge_requests?state=opened&approved=yes"

func Revoke(projectId string) {

	gitCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")

	output, err := gitCmd.Output()
	if err != nil {
		log.Fatalf("Error running git rev-parse: %s", err)
	}

	sourceBranch := strings.TrimSpace(string(output))

	canBeRevoked := checkCanBeRevoked(projectId, sourceBranch)

	if !canBeRevoked {
		log.Fatal("Merge request can not be revoked")
	}

	cmd := exec.Command("glab", "mr", "revoke")

	stdoutPipe, err := cmd.StdoutPipe()
	if err != nil {
		log.Fatalf("Failed to create stdout pipe: %s", err)
	}

	stderrPipe, err := cmd.StderrPipe()
	if err != nil {
		log.Fatalf("Failed to create stderr pipe: %s", err)
	}

	err = cmd.Start()
	if err != nil {
		log.Fatalf("Failed to start command: %s", err)
	}

	go func() {
		// Read from stdoutPipe and print to stdout
		scanner := bufio.NewScanner(stdoutPipe)
		for scanner.Scan() {
			fmt.Println(scanner.Text())
		}

		if err := scanner.Err(); err != nil {
			log.Fatalf("Failed to read stdout: %s", err)
		}
	}()

	go func() {
		// Read from stderrPipe and print to stderr
		scanner := bufio.NewScanner(stderrPipe)
		for scanner.Scan() {
			fmt.Fprintln(os.Stderr, scanner.Text())
		}

		if err := scanner.Err(); err != nil {
			log.Fatalf("Failed to read stderr: %s", err)
		}
	}()

	err = cmd.Wait()
	if err != nil {
		log.Fatalf("Error approving MR: %s", err)
	}
}

func checkCanBeRevoked(projectId string, sourceBranch string) bool {
	req, err := http.NewRequest(http.MethodGet, fmt.Sprintf(revokeUrl, projectId), nil)
	if err != nil {
		log.Fatal("Failed to create request: ", err)
	}

	client := &http.Client{}

	res, err := client.Do(req)
	if err != nil {
		log.Fatal("Error checking MR status: ", err)
	}

	if res.StatusCode == 404 {
		log.Fatalf("No open merge request for this branch")
	}

	body, err := ioutil.ReadAll(res.Body)

	if err != nil {
		log.Fatal("Error reading response body: ", err)
	}

	var jsonData []MergeRequest
	err = json.Unmarshal(body, &jsonData)
	if err != nil {
		log.Fatal("Error unmarshaling JSON response: ", err)
	}

	if len(jsonData) == 0 {
		return false
	}

	if jsonData[0].SourceBranch == sourceBranch {
		return true
	}

	return false
}
