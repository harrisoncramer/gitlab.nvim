package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"time"
)

type f func(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo)

func StartServer(client HandlerClient, projectInfo *ProjectInfo) {
	m := http.NewServeMux()
	m.Handle("/ping", http.HandlerFunc(PingHandler))
	m.Handle("/info", Middleware(client, projectInfo, InfoHandler))
	m.Handle("/mr/summary", Middleware(client, projectInfo, SummaryHandler))
	m.Handle("/mr/attachment", Middleware(client, projectInfo, AttachmentHandler))
	m.Handle("/mr/reviewer", Middleware(client, projectInfo, ReviewersHandler))
	m.Handle("/mr/revisions", Middleware(client, projectInfo, RevisionsHandler))
	m.Handle("/mr/assignee", Middleware(client, projectInfo, AssigneesHandler))
	m.Handle("/approve", Middleware(client, projectInfo, ApproveHandler))
	m.Handle("/revoke", Middleware(client, projectInfo, RevokeHandler))
	m.Handle("/discussions", Middleware(client, projectInfo, ListDiscussionsHandler))
	m.Handle("/discussion/resolve", Middleware(client, projectInfo, DiscussionResolveHandler))
	// m.Handle("/comment", Middleware(client, projectInfo, CommentHandler))
	// m.Handle("/reply", Middleware(client, projectInfo, ReplyHandler))
	// m.Handle("/members", Middleware(client, projectInfo, ProjectMembersHandler))
	// m.Handle("/pipeline", Middleware(client, projectInfo, PipelineHandler))
	// m.Handle("/job", Middleware(client, projectInfo, JobHandler))
	startServer(m)
}

func Middleware(client HandlerClient, projectInfo *ProjectInfo, handler f) http.HandlerFunc {

	return func(w http.ResponseWriter, r *http.Request) {
		handler(w, r, client, projectInfo)
	}
}

func startServer(m *http.ServeMux) {
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
