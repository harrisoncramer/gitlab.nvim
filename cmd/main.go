package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/xanzy/go-gitlab"
)

func main() {
	gitInfo, err := ExtractGitInfo(RefreshProjectInfo, GetProjectUrlFromNativeGitCmd, GetCurrentBranchNameFromNativeGitCmd)
	if err != nil {
		log.Fatalf("Failure initializing plugin with `git` commands: %v", err)
	}

	err, client := InitGitlabClient()
	if err != nil {
		log.Fatalf("Failed to initialize Gitlab client: %v", err)
	}

	err, projectInfo := InitProjectSettings(client, gitInfo)
	if err != nil {
		log.Fatalf("Failed to initialize project settings: %v", err)
	}

	m := http.NewServeMux()
	m.Handle("/ping", http.HandlerFunc(PingHandler))
	m.Handle("/mr/summary", withGitlabContext(http.HandlerFunc(SummaryHandler), client, projectInfo))
	m.Handle("/mr/attachment", withGitlabContext(http.HandlerFunc(AttachmentHandler), client, projectInfo))
	m.Handle("/mr/reviewer", withGitlabContext(http.HandlerFunc(ReviewersHandler), client, projectInfo))
	m.Handle("/mr/revisions", withGitlabContext(http.HandlerFunc(RevisionsHandler), client, projectInfo))
	m.Handle("/mr/assignee", withGitlabContext(http.HandlerFunc(AssigneesHandler), client, projectInfo))
	m.Handle("/approve", withGitlabContext(http.HandlerFunc(ApproveHandler), client, projectInfo))
	m.Handle("/revoke", withGitlabContext(http.HandlerFunc(RevokeHandler), client, projectInfo))
	m.Handle("/info", withGitlabContext(http.HandlerFunc(InfoHandler), client, projectInfo))
	m.Handle("/discussions", withGitlabContext(http.HandlerFunc(ListDiscussionsHandler), client, projectInfo))
	m.Handle("/discussion/resolve", withGitlabContext(http.HandlerFunc(DiscussionResolveHandler), client, projectInfo))
	m.Handle("/comment", withGitlabContext(http.HandlerFunc(CommentHandler), client, projectInfo))
	m.Handle("/reply", withGitlabContext(http.HandlerFunc(ReplyHandler), client, projectInfo))
	m.Handle("/members", withGitlabContext(http.HandlerFunc(ProjectMembersHandler), client, projectInfo))
	m.Handle("/pipeline", withGitlabContext(http.HandlerFunc(PipelineHandler), client, projectInfo))
	m.Handle("/job", withGitlabContext(http.HandlerFunc(JobHandler), client, projectInfo))

	port := os.Args[2]
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
	listenerPort := listener.Addr().(*net.TCPAddr).Port

	errCh := make(chan error)
	go func() {
		err := http.Serve(listener, m)
		errCh <- err
	}()

	go func() {
		for i := 0; i < 10; i++ {
			resp, err := http.Get("http://localhost:" + fmt.Sprintf("%d", listenerPort) + "/ping")
			if resp.StatusCode == 200 && err == nil {
				/* This print is detected by the Lua code and used to fetch project information */
				fmt.Println("Server started on port: ", listenerPort)
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

func PingHandler(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "pong")
}

func withGitlabContext(next http.HandlerFunc, c *gitlab.Client, d *ProjectInfo) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctxWithClient := context.WithValue(context.Background(), "client", c) //nolint:all
		ctxWithData := context.WithValue(ctxWithClient, "data", d)            //nolint:all
		next.ServeHTTP(w, r.WithContext(ctxWithData))
	})
}
