package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

func main() {
	branchName, err := getCurrentBranch()

	if err != nil {
		log.Fatalf("Failure: Failed to get current branch: %v", err)
	}

	if branchName == "main" || branchName == "master" {
		log.Fatalf("Cannot run on %s branch", branchName)
	}

	/* Initialize Gitlab client */
	var c Client

	if err := c.init(branchName); err != nil {
		log.Fatalf("Failed to initialize Gitlab client: %v", err)
	}

	m := http.NewServeMux()
	m.Handle("/ping", http.HandlerFunc(PingHandler))
	m.Handle("/mr/summary", withGitlabContext(http.HandlerFunc(SummaryHandler), c))
	m.Handle("/mr/attachment", withGitlabContext(http.HandlerFunc(AttachmentHandler), c))
	m.Handle("/mr/reviewer", withGitlabContext(http.HandlerFunc(ReviewersHandler), c))
	m.Handle("/mr/revisions", withGitlabContext(http.HandlerFunc(RevisionsHandler), c))
	m.Handle("/mr/assignee", withGitlabContext(http.HandlerFunc(AssigneesHandler), c))
	m.Handle("/approve", withGitlabContext(http.HandlerFunc(ApproveHandler), c))
	m.Handle("/revoke", withGitlabContext(http.HandlerFunc(RevokeHandler), c))
	m.Handle("/info", withGitlabContext(http.HandlerFunc(InfoHandler), c))
	m.Handle("/discussions", withGitlabContext(http.HandlerFunc(ListDiscussionsHandler), c))
	m.Handle("/comment", withGitlabContext(http.HandlerFunc(CommentHandler), c))
	m.Handle("/reply", withGitlabContext(http.HandlerFunc(ReplyHandler), c))
	m.Handle("/members", withGitlabContext(http.HandlerFunc(ProjectMembersHandler), c))
	m.Handle("/pipeline", withGitlabContext(http.HandlerFunc(PipelineHandler), c))
	m.Handle("/job", withGitlabContext(http.HandlerFunc(JobHandler), c))

	port := os.Args[3]
	if port == "" {
		// port was not specified
		port = "0"
	}
	addr := fmt.Sprintf("localhost:%s", port)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatal(err)
		fmt.Fprintf(os.Stderr, "Error starting server: %s\n", err)
		os.Exit(1)
	}
	listner_port := listener.Addr().(*net.TCPAddr).Port

	errCh := make(chan error)
	go func() {
		err := http.Serve(listener, m)
		errCh <- err
	}()

	go func() {
		for i := 0; i < 10; i++ {
			resp, err := http.Get("http://localhost:" + fmt.Sprintf("%d", listner_port) + "/ping")
			if resp.StatusCode == 200 && err == nil {
				/* This print is detected by the Lua code and used to fetch project information */
				fmt.Println("Server started on port: ", listner_port)
				return
			}
			// Wait for healthcheck to pass - at most 1 sec.
			time.Sleep(100 * time.Microsecond)
		}
		errCh <- err
	}()

	if err := <-errCh; err != nil {
		fmt.Fprintf(os.Stderr, "Error starting server: %s\n", err)
		os.Exit(1)
	}

}

func withGitlabContext(next http.HandlerFunc, c Client) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := context.WithValue(context.Background(), "client", c)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

/* Gets the current branch */
func getCurrentBranch() (res string, e error) {
	gitCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")

	output, err := gitCmd.Output()
	if err != nil {
		return "", fmt.Errorf("Error running git rev-parse: %w", err)
	}

	return strings.TrimSpace(string(output)), nil
}
func PingHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "pong")
}
