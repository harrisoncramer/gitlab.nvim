package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"
)

/*
startSever starts the server and runs concurrent goroutines
to handle potential shutdown requests and incoming HTTP requests.
*/
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
		err := server.Serve(l)
		if err != nil {
			if errors.Is(err, http.ErrServerClosed) {
				os.Exit(0)
			} else {
				fmt.Fprintf(os.Stderr, "Server did not respond: %s\n", err)
				os.Exit(1)
			}
		}
	}()

	port := l.Addr().(*net.TCPAddr).Port
	err := checkServer(port)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Server did not respond: %s\n", err)
		os.Exit(1)
	}

	/* This print is detected by the Lua code */
	fmt.Println("Server started on port: ", port)

	/* Handles shutdown requests */
	<-a.sigCh
	err = server.Shutdown(context.Background())
	if err != nil {
		fmt.Fprintf(os.Stderr, "Server could not shut down gracefully: %s\n", err)
		os.Exit(1)
	} else {
		os.Exit(0)
	}
}

/*
The api struct contains common configuration that's accessible to all handlers, such as the gitlab
client, the project information, and the channels for signaling error or shutdown requests

The handlers for different Gitlab operations are are all methods on the api struct and interact
with the client value, which is a go-gitlab client.
*/
type api struct {
	client      ClientInterface
	projectInfo *ProjectInfo
	fileReader  FileReader
	sigCh       chan os.Signal
}

type optFunc func(a *api) error

/*
createRouterAndApi wires up the router and attaches all handlers to their respective routes. It also
iterates over all option functions to configure API fields such as the project information and default
file reader functionality
*/
func createRouterAndApi(client ClientInterface, optFuncs ...optFunc) (*http.ServeMux, api) {
	m := http.NewServeMux()
	a := api{
		client:      client,
		projectInfo: &ProjectInfo{},
		fileReader:  nil,
		sigCh:       make(chan os.Signal, 1),
	}

	/* Mutates the API struct as necessary with configuration functions */
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
	m.HandleFunc("/merge", a.acceptAndMergeHandler)
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

/* checkServer pings the server repeatedly for 1 full second after startup in order to notify the plugin that the server is ready */
func checkServer(port int) error {
	for i := 0; i < 10; i++ {
		resp, err := http.Get("http://localhost:" + fmt.Sprintf("%d", port) + "/ping")
		if resp.StatusCode == 200 && err == nil {
			return nil
		}
		time.Sleep(100 * time.Microsecond)
	}

	return errors.New("Could not start server!")
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
