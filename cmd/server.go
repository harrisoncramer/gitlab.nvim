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

/* This function wires up the router and attaches all handlers to their respective routes. It then starts up the server on the port specified or on a random port */
func Start(client HandlerClient, projectInfo *ProjectInfo) {
	m := http.NewServeMux()

	m.Handle("/ping", http.HandlerFunc(pingHandler))
	m.Handle("/info", withClient(client, projectInfo, infoHandler))
	m.Handle("/mr/summary", withClient(client, projectInfo, summaryHandler))
	m.Handle("/mr/attachment", withFileReader(withClient(client, projectInfo, attachmentHandler)))
	m.Handle("/mr/reviewer", withClient(client, projectInfo, reviewersHandler))
	m.Handle("/mr/revisions", withClient(client, projectInfo, revisionsHandler))
	m.Handle("/mr/assignee", withClient(client, projectInfo, assigneesHandler))
	m.Handle("/approve", withClient(client, projectInfo, approveHandler))
	m.Handle("/revoke", withClient(client, projectInfo, revokeHandler))
	m.Handle("/discussions/list", withClient(client, projectInfo, listDiscussionsHandler))
	m.Handle("/discussions/resolve", withClient(client, projectInfo, discussionsResolveHandler))
	m.Handle("/comment", withClient(client, projectInfo, commentHandler))
	m.Handle("/reply", withClient(client, projectInfo, replyHandler))
	m.Handle("/project/members", withClient(client, projectInfo, projectMembersHandler))
	m.Handle("/pipeline/", withClient(client, projectInfo, pipelineHandler))
	m.Handle("/job", withClient(client, projectInfo, jobHandler))
	startServer(m)
}

/* This function attempts to start the port on the port specified in the configuration if present, otherwise it chooses a random port */
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

func pingHandler(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "pong")
}
