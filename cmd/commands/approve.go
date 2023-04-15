package commands

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"os/exec"
)

const approvalUrl = "https://gitlab.com/api/v4/projects/%s/merge_requests?state=opened&approved=no"

func Approve(projectId string) {

	sourceBranch := GetCurrentBranch()
	canBeApproved := canBeApproved(projectId, sourceBranch)
	if !canBeApproved {
		log.Fatal("Merge request can not be approved")
	}

	cmd := exec.Command("glab", "mr", "approve")

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

func canBeApproved(projectId string, sourceBranch string) bool {
	mrs := GetMRs(fmt.Sprintf(approvalUrl, projectId))

	if len(mrs) == 0 {
		return false
	}

	if mrs[0].SourceBranch == sourceBranch {
		return true
	}

	return false
}
