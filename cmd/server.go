package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/xanzy/go-gitlab"
)

/*
startSever starts the server and runs concurrent goroutines
to handle potential shutdown requests and incoming HTTP requests.
*/
func startServer(client *Client, projectInfo *ProjectInfo, gitInfo GitProjectInfo) {

	m, a := createRouterAndApi(client,
		func(a *api) error {
			a.projectInfo = projectInfo
			return nil
		},
		func(a *api) error {
			a.fileReader = attachmentReader{}
			return nil
		},
		func(a *api) error {
			a.gitInfo = &gitInfo
			return nil
		},
		func(a *api) error {
			err := attachEmojisToApi(a)
			return err
		},
		func(a *api) error {
			a.gitInfo.GetLatestCommitOnRemote = GetLatestCommitOnRemote
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
	gitInfo     *GitProjectInfo
	fileReader  FileReader
	emojiMap    EmojiMap
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
		gitInfo:     &GitProjectInfo{},
		fileReader:  nil,
		emojiMap:    EmojiMap{},
		sigCh:       make(chan os.Signal, 1),
	}

	/* Mutates the API struct as necessary with configuration functions */
	for _, optFunc := range optFuncs {
		err := optFunc(&a)
		if err != nil {
			panic(err)
		}
	}

	m.HandleFunc("/mr/approve", a.withMr(a.approveHandler))
	m.HandleFunc("/mr/comment", a.withMr(a.commentHandler))
	m.HandleFunc("/mr/merge", a.withMr(a.acceptAndMergeHandler))
	m.HandleFunc("/mr/discussions/list", a.withMr(a.listDiscussionsHandler))
	m.HandleFunc("/mr/discussions/resolve", a.withMr(a.discussionsResolveHandler))
	m.HandleFunc("/mr/info", a.withMr(a.infoHandler))
	m.HandleFunc("/mr/assignee", a.withMr(a.assigneesHandler))
	m.HandleFunc("/mr/summary", a.withMr(a.summaryHandler))
	m.HandleFunc("/mr/reviewer", a.withMr(a.reviewersHandler))
	m.HandleFunc("/mr/revisions", a.withMr(a.revisionsHandler))
	m.HandleFunc("/mr/reply", a.withMr(a.replyHandler))
	m.HandleFunc("/mr/label", a.withMr(a.labelHandler))
	m.HandleFunc("/mr/revoke", a.withMr(a.revokeHandler))
	m.HandleFunc("/mr/awardable/note/", a.withMr(a.emojiNoteHandler))

	m.HandleFunc("/pipeline", a.pipelineHandler)
	m.HandleFunc("/pipeline/trigger/", a.pipelineHandler)
	m.HandleFunc("/users/me", a.meHandler)
	m.HandleFunc("/attachment", a.attachmentHandler)
	m.HandleFunc("/create_mr", a.createMr)
	m.HandleFunc("/job", a.jobHandler)
	m.HandleFunc("/project/members", a.projectMembersHandler)
	m.HandleFunc("/shutdown", a.shutdownHandler)

	m.Handle("/ping", http.HandlerFunc(pingHandler))

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

/* withMr is a Middlware that gets the current merge request ID and attaches it to the projectInfo */
func (a *api) withMr(f func(w http.ResponseWriter, r *http.Request)) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {

		if a.projectInfo.MergeId != 0 {
			f(w, r)
			return
		}

		options := gitlab.ListProjectMergeRequestsOptions{
			Scope:        gitlab.String("all"),
			State:        gitlab.String("opened"),
			SourceBranch: &a.gitInfo.BranchName,
		}

		mergeRequests, _, err := a.client.ListProjectMergeRequests(a.projectInfo.ProjectId, &options)
		if err != nil {
			handleError(w, fmt.Errorf("Failed to list merge requests: %w", err), "Failed to list merge requests", http.StatusInternalServerError)
			return
		}

		if len(mergeRequests) == 0 {
			handleError(w, fmt.Errorf("No merge requests found for branch '%s'", a.gitInfo.BranchName), "No merge requests found", http.StatusBadRequest)
			return
		}

		mergeId := strconv.Itoa(mergeRequests[0].IID)
		mergeIdInt, err := strconv.Atoi(mergeId)
		if err != nil {
			handleError(w, err, "Could not convert merge ID to integer", http.StatusBadRequest)
			return
		}

		a.projectInfo.MergeId = mergeIdInt
		f(w, r)
	}
}
