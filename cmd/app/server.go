package app

import (
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/xanzy/go-gitlab"
	"gitlab.com/harrisoncramer/gitlab.nvim/cmd/app/git"
)

/*
startSever starts the server and runs concurrent goroutines
to handle potential shutdown requests and incoming HTTP requests.
*/
func StartServer(client *Client, projectInfo *ProjectInfo, GitInfo git.GitProjectInfo) {

	s := shutdown{
		sigCh: make(chan os.Signal, 1),
	}

	m, _ := CreateRouterAndApi(
		client,
		projectInfo,
		s,
		func(a *Api) error { a.projectInfo = projectInfo; return nil },
		func(a *Api) error { a.fileReader = attachmentReader{}; return nil },
		func(a *Api) error { a.GitInfo = &GitInfo; return nil },
		func(a *Api) error { err := attachEmojisToApi(a); return err },
		func(a *Api) error { a.GitInfo.GetLatestCommitOnRemote = git.GetLatestCommitOnRemote; return nil },
	)
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
	s.WatchForShutdown(server)
}

/*
The Api struct contains common configuration that's accessible to all handlers, such as the gitlab
client, the project information, and the channels for signaling error or shutdown requests

The handlers for different Gitlab operations are are all methods on the Api struct and interact
with the client value, which is a go-gitlab client.
*/
type Api struct {
	client      ClientInterface
	projectInfo *ProjectInfo
	GitInfo     *git.GitProjectInfo
	fileReader  FileReader
	emojiMap    EmojiMap
}

type optFunc func(a *clientWithInfo) error

/*
CreateRouterAndApi wires up the router and attaches all handlers to their respective routes. It also
iterates over all option functions to configure API fields such as the project information and default
file reader functionality
*/

type clientWithInfo struct {
	gitlabClient *Client
	projectInfo  *ProjectInfo
	gitInfo      *git.GitProjectInfo
}

func CreateRouterAndApi(gitlabClient *Client, projectInfo *ProjectInfo, s ShutdownHandler, optFuncs ...optFunc) (*http.ServeMux, clientWithInfo) {
	m := http.NewServeMux()

	// a := Api{
	// 	client:      client,
	// 	projectInfo: &ProjectInfo{},
	// 	GitInfo:     &git.GitProjectInfo{},
	// 	fileReader:  nil,
	// 	emojiMap:    EmojiMap{},
	// }

	c := clientWithInfo{
		gitlabClient: gitlabClient,
		projectInfo:  &ProjectInfo{},
		gitInfo:      &git.GitProjectInfo{},
	}

	/* Mutates the API struct as necessary with configuration functions */
	for _, optFunc := range optFuncs {
		err := optFunc(&c)
		if err != nil {
			panic(err)
		}
	}

	// m.HandleFunc("/mr/approve", a.withMr(a.approveHandler))
	// m.HandleFunc("/mr/comment", a.withMr(a.commentHandler))
	// m.HandleFunc("/mr/merge", a.withMr(a.acceptAndMergeHandler))
	// m.HandleFunc("/mr/discussions/list", a.withMr(a.listDiscussionsHandler))
	// m.HandleFunc("/mr/discussions/resolve", a.withMr(a.discussionsResolveHandler))
	// m.HandleFunc("/mr/info", a.withMr(a.infoHandler))
	// m.HandleFunc("/mr/assignee", a.withMr(a.assigneesHandler))
	// m.HandleFunc("/mr/summary", a.withMr(a.summaryHandler))
	// m.HandleFunc("/mr/reviewer", a.withMr(a.reviewersHandler))
	// m.HandleFunc("/mr/revisions", a.withMr(a.revisionsHandler))
	// m.HandleFunc("/mr/reply", a.withMr(a.replyHandler))
	// m.HandleFunc("/mr/label", a.withMr(a.labelHandler))
	// m.HandleFunc("/mr/revoke", a.withMr(a.revokeHandler))
	// m.HandleFunc("/mr/awardable/note/", a.withMr(a.emojiNoteHandler))
	// m.HandleFunc("/mr/draft_notes/", a.withMr(a.draftNoteHandler))
	// m.HandleFunc("/mr/draft_notes/publish", a.withMr(a.draftNotePublisher))
	m.HandleFunc("/pipeline", pipelineService{c}.handler)
	m.HandleFunc("/pipeline/trigger/", pipelineService{c}.handler)
	m.HandleFunc("/users/me", meService{c}.handler)
	m.HandleFunc("/attachment", attachmentService{clientWithInfo: c, fileReader: attachmentReader{}}.handler)
	m.HandleFunc("/create_mr", mergeRequestCreatorService{c}.handler)
	m.HandleFunc("/job", traceFileService{c}.handler)
	m.HandleFunc("/project/members", projectListerService{c}.handler)
	m.HandleFunc("/merge_requests", withMr(mergeRequestListerService{c}.handler, c))

	m.HandleFunc("/shutdown", s.shutdownHandler)
	m.Handle("/ping", http.HandlerFunc(pingHandler))

	return m, c
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
	addr := fmt.Sprintf("localhost:%d", pluginOptions.Port)
	l, err := net.Listen("tcp", addr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error starting server: %s\n", err)
		os.Exit(1)
	}

	return l
}

/* withMr is a Middlware that gets the current merge request ID and attaches it to the projectInfo */
func withMr(next http.HandlerFunc, client clientWithInfo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// If the merge request is already attached, skip the middleware logic
		if client.projectInfo.MergeId == 0 {
			options := gitlab.ListProjectMergeRequestsOptions{
				Scope:        gitlab.Ptr("all"),
				State:        gitlab.Ptr("opened"),
				SourceBranch: &client.gitInfo.BranchName,
			}

			mergeRequests, _, err := client.gitlabClient.ListProjectMergeRequests(client.projectInfo.ProjectId, &options)
			if err != nil {
				handleError(w, fmt.Errorf("Failed to list merge requests: %w", err), "Failed to list merge requests", http.StatusInternalServerError)
				return
			}

			if len(mergeRequests) == 0 {
				err := fmt.Errorf("No merge requests found for branch '%s'", client.gitInfo.BranchName)
				handleError(w, err, "No merge requests found", http.StatusBadRequest)
				return
			}

			mergeIdInt := mergeRequests[0].IID
			client.projectInfo.MergeId = mergeIdInt
		}

		// Call the next handler if middleware succeeds
		next(w, r)
	}
}
