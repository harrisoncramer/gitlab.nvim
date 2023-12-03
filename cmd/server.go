package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"
)

/* Initializes the api, router, and server and starts the server */
func startServer(client *Client, projectInfo *ProjectInfo) {

	/* Adds the server configuration to the API struct */
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

type api struct {
	client      ClientInterface
	projectInfo *ProjectInfo
	fileReader  FileReader
	sigCh       chan os.Signal
	errCh       chan error
}

type optFunc func(a *api) error

/* Wires up the router and attaches all handlers to their respective routes. */
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

/* Used to check whether the server has started yet */
func pingHandler(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "pong")
}

/* Checks the server for 1 full second after startup in order to notify the plugin that the server is ready */
func start(eChan chan error, port int) {
	var err error
	for i := 0; i < 10; i++ {
		resp, err := http.Get("http://localhost:" + fmt.Sprintf("%d", port) + "/ping")
		if resp.StatusCode == 200 && err == nil {
			fmt.Println("Server started on port: ", port) /* This print is detected by the Lua code */
			return
		}
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
		port = "0"
	}
	addr := fmt.Sprintf("localhost:%s", port)
	l, err := net.Listen("tcp", addr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error starting server: %s\n", err)
		os.Exit(1)
	}

	return l
}
