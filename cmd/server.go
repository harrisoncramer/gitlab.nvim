package main

import (
	"fmt"
	"io"
	"log"
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
}

/* This function wires up the router and attaches all handlers to their respective routes. It then starts up the server on the port specified or on a random port */
func createServer(client ClientInterface, projectInfo *ProjectInfo, fileReader FileReader) *http.ServeMux {
	m := http.NewServeMux()

	c := api{
		client:      client,
		projectInfo: projectInfo,
		fileReader:  fileReader,
	}

	m.Handle("/ping", http.HandlerFunc(pingHandler))

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
