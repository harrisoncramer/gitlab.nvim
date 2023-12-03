package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"
)

type api struct {
	client      ClientInterface
	projectInfo *ProjectInfo
	fileReader  FileReader
	sigCh       chan os.Signal
	errCh       chan error
}

type optFunc func(a *api) error

/* This function wires up the router and attaches all handlers to their respective routes. It then starts up the server on the port specified or on a random port */
func createRouterAndApi(client ClientInterface, optFuncs ...optFunc) (*http.ServeMux, api) {
	m := http.NewServeMux()
	a := api{
		client:      client,
		projectInfo: &ProjectInfo{},
		fileReader:  attachmentReader{},
		sigCh:       make(chan os.Signal, 1),
		errCh:       make(chan error),
	}

	for _, optFunc := range optFuncs {
		err := optFunc(&a)
		if err != nil {
			panic(err)
		}
	}

	m.Handle("/ping", http.HandlerFunc(pingHandler))
	m.HandleFunc("/shutdown", a.shutdownHandler)
	m.HandleFunc("/approve", a.approveHandler)
	m.HandleFunc("/comment", a.commentHandler)
	m.HandleFunc("/discussions/list", a.listDiscussionsHandler)
	m.HandleFunc("/discussions/resolve", a.discussionsResolveHandler)
	m.HandleFunc("/info", a.infoHandler)
	m.HandleFunc("/job", a.jobHandler)
	m.HandleFunc("/mr/attachment", a.attachmentHandler)
	m.HandleFunc("/mr/assignee", a.assigneesHandler)
	m.HandleFunc("/mr/summary", a.summaryHandler)
	m.HandleFunc("/mr/reviewer", a.reviewersHandler)
	m.HandleFunc("/mr/revisions", a.revisionsHandler)
	m.HandleFunc("/pipeline/", a.pipelineHandler)
	m.HandleFunc("/project/members", a.projectMembersHandler)
	m.HandleFunc("/reply", a.replyHandler)
	m.HandleFunc("/revoke", a.revokeHandler)

	return m, a
}

/* This function attempts to start the port on the port specified in the configuration if present, otherwise it chooses a random port */
func startServer(client *Client, projectInfo *ProjectInfo) {

	m, a := createRouterAndApi(client,
		func(a *api) error {
			a.projectInfo = projectInfo
			return nil
		},
		func(a *api) error {
			a.fileReader = attachmentReader{}
			return nil
		})

	l := createListener()
	server := &http.Server{Handler: m}

	/* Starts the Go server */
	go func() {
		server.Serve(l)
	}()

	/* Handles shutdown requests */
	go func() {
		<-a.sigCh
		server.Shutdown(context.Background())
		os.Exit(0)
	}()

	/* Handles errors */
	go func() {
		<-a.sigCh
		server.Shutdown(context.Background())
		os.Exit(0)
	}()

	/* Alerts Lua when the server has started */
	port := l.Addr().(*net.TCPAddr).Port
	go start(a.errCh, port)

	if err := <-a.errCh; err != nil {
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
