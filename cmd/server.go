package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"time"
)

/* TODO: Convert the server configuration + this into optional function pattern */
type FileReader interface {
	ReadFile(path string) (io.Reader, error)
}

type api struct {
	client      ClientInterface
	projectInfo *ProjectInfo
	fileReader  FileReader
	sigCh       chan os.Signal
	errCh       chan error
}

/* This function wires up the router and attaches all handlers to their respective routes. It then starts up the server on the port specified or on a random port */
func createServer(client ClientInterface, projectInfo *ProjectInfo, fileReader FileReader, sigCh chan os.Signal, errCh chan error) *http.ServeMux {
	m := http.NewServeMux()
	c := api{
		client:      client,
		projectInfo: projectInfo,
		fileReader:  fileReader,
		sigCh:       sigCh,
		errCh:       errCh,
	}

	m.Handle("/ping", http.HandlerFunc(pingHandler))
	m.HandleFunc("/shutdown", c.shutdownHandler)
	m.HandleFunc("/approve", c.approveHandler)
	m.HandleFunc("/comment", c.commentHandler)
	m.HandleFunc("/discussions/list", c.listDiscussionsHandler)
	m.HandleFunc("/discussions/resolve", c.discussionsResolveHandler)
	m.HandleFunc("/info", c.infoHandler)
	m.HandleFunc("/job", c.jobHandler)
	m.HandleFunc("/mr/attachment", c.attachmentHandler)
	m.HandleFunc("/mr/assignee", c.assigneesHandler)
	m.HandleFunc("/mr/summary", c.summaryHandler)
	m.HandleFunc("/mr/reviewer", c.reviewersHandler)
	m.HandleFunc("/mr/revisions", c.revisionsHandler)
	m.HandleFunc("/pipeline/", c.pipelineHandler)
	m.HandleFunc("/project/members", c.projectMembersHandler)
	m.HandleFunc("/reply", c.replyHandler)
	m.HandleFunc("/revoke", c.revokeHandler)

	return m
}

/* This function attempts to start the port on the port specified in the configuration if present, otherwise it chooses a random port */
func startServer(client *Client, projectInfo *ProjectInfo) {

	sigCh := make(chan os.Signal, 1)
	errCh := make(chan error)
	m := createServer(client, projectInfo, attachmentReader{}, sigCh, errCh)

	l := createListener()
	server := &http.Server{Handler: m}

	/* Starts the Go server */
	go func() {
		server.Serve(l)
	}()

	/* Handles shutdown requests */
	go func() {
		<-sigCh
		server.Shutdown(context.Background())
	}()

	/* Handles errors */
	go func() {
		<-sigCh
		server.Shutdown(context.Background())
	}()

	/* Alerts Lua when the server has started */
	port := l.Addr().(*net.TCPAddr).Port
	go start(errCh, port)

	if err := <-errCh; err != nil {
		fmt.Fprintf(os.Stderr, "Error starting server: %s\n", err)
		os.Exit(1)
	}
}

func pingHandler(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "pong")
}

/* Alerts us when the server has started */
func start(eChan chan error, port int) {
	var err error
	for i := 0; i < 10; i++ {
		resp, err := http.Get("http://localhost:" + fmt.Sprintf("%d", port) + "/ping")
		if resp.StatusCode == 200 && err == nil {
			/* This print is detected by the Lua code and used to fetch project information */
			fmt.Println("Server started on port: ", port)
			return
		}
		// Wait for healthcheck to pass - at most 1 sec.
		time.Sleep(100 * time.Microsecond)
	}

	if err != nil {
		eChan <- err
	}
}

/* Creates a TCP listener on the port specified by the user or a random port */
func createListener() (l net.Listener) {
	port := os.Args[2]
	if port == "" {
		port = "0" /* Random port if not specified */
	}
	addr := fmt.Sprintf("localhost:%s", port)
	l, err := net.Listen("tcp", addr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error starting server: %s\n", err)
		os.Exit(1)
	}

	return l

}
