package commands

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"os/exec"
)

const revokeUrl = "https://gitlab.com/api/v4/projects/%s/merge_requests?state=opened&approved=yes"

func Revoke(projectId string) {

	sourceBranch := GetCurrentBranch()
	canBeRevoked := canBeRevoked(projectId, sourceBranch)
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

func canBeRevoked(projectId string, sourceBranch string) bool {
	mrs := GetMRs(fmt.Sprintf(revokeUrl, projectId))

	if len(mrs) == 0 {
		return false
	}

	if mrs[0].SourceBranch == sourceBranch {
		return true
	}

	return false
}
