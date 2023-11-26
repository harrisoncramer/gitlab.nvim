package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"time"
)

type handlerFunc func(w http.ResponseWriter, r *http.Request, c HandlerClient, d *ProjectInfo)

func StartServer(client HandlerClient, projectInfo *ProjectInfo) {
	m := http.NewServeMux()

	m.Handle("/ping", http.HandlerFunc(PingHandler))
	m.Handle("/info", ClientMiddleware(client, projectInfo, InfoHandler))
	m.Handle("/mr/summary", ClientMiddleware(client, projectInfo, SummaryHandler))
	m.Handle("/mr/attachment", FileMiddleware(ClientMiddleware(client, projectInfo, AttachmentHandler)))
	m.Handle("/mr/reviewer", ClientMiddleware(client, projectInfo, ReviewersHandler))
	m.Handle("/mr/revisions", ClientMiddleware(client, projectInfo, RevisionsHandler))
	m.Handle("/mr/assignee", ClientMiddleware(client, projectInfo, AssigneesHandler))
	m.Handle("/approve", ClientMiddleware(client, projectInfo, ApproveHandler))
	m.Handle("/revoke", ClientMiddleware(client, projectInfo, RevokeHandler))
	m.Handle("/discussions/list", ClientMiddleware(client, projectInfo, ListDiscussionsHandler))
	m.Handle("/discussion/resolve", ClientMiddleware(client, projectInfo, DiscussionResolveHandler))
	m.Handle("/comment", ClientMiddleware(client, projectInfo, CommentHandler))
	m.Handle("/reply", ClientMiddleware(client, projectInfo, ReplyHandler))
	m.Handle("/members", ClientMiddleware(client, projectInfo, ProjectMembersHandler))
	m.Handle("/pipeline", ClientMiddleware(client, projectInfo, PipelineHandler))
	m.Handle("/job", ClientMiddleware(client, projectInfo, JobHandler))
	startServer(m)
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
