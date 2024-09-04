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

type optFunc func(a *commonHandlerData) error

/*
CreateRouterAndApi wires up the router and attaches all handlers to their respective routes. It also
iterates over all option functions to configure API fields such as the project information and default
file reader functionality
*/

type commonHandlerData struct {
	projectInfo *ProjectInfo
	gitInfo     *git.GitProjectInfo
}

func CreateRouterAndApi(gitlabClient *Client, projectInfo *ProjectInfo, s ShutdownHandler, optFuncs ...optFunc) (*http.ServeMux, commonHandlerData) {
	m := http.NewServeMux()

	c := commonHandlerData{
		projectInfo: &ProjectInfo{},
		gitInfo:     &git.GitProjectInfo{},
	}

	/* Mutates the API struct as necessary with configuration functions */
	for _, optFunc := range optFuncs {
		err := optFunc(&c)
		if err != nil {
			panic(err)
		}
	}

	// m.HandleFunc("/mr/approve", withMr(a.approveHandler))
	// m.HandleFunc("/mr/comment", withMr(a.commentHandler))
	// m.HandleFunc("/mr/merge", withMr(a.acceptAndMergeHandler))
	// m.HandleFunc("/mr/discussions/list", withMr(a.listDiscussionsHandler))
	// m.HandleFunc("/mr/discussions/resolve", withMr(a.discussionsResolveHandler))
	// m.HandleFunc("/mr/info", withMr(a.infoHandler))
	// m.HandleFunc("/mr/assignee", withMr(a.assigneesHandler))
	// m.HandleFunc("/mr/summary", withMr(a.summaryHandler))
	// m.HandleFunc("/mr/reviewer", withMr(a.reviewersHandler))
	// m.HandleFunc("/mr/revisions", withMr(a.revisionsHandler))
	// m.HandleFunc("/mr/reply", withMr(a.replyHandler))
	// m.HandleFunc("/mr/label", withMr(a.labelHandler))
	// m.HandleFunc("/mr/revoke", withMr(a.revokeHandler))
	// m.HandleFunc("/mr/awardable/note/", withMr(a.emojiNoteHandler))
	// m.HandleFunc("/mr/draft_notes/", withMr(a.draftNoteHandler))
	m.HandleFunc("/mr/draft_notes/publish", withMr(draftNoteService{commonHandlerData: c, client: gitlabClient}.handler, c, gitlabClient))

	m.HandleFunc("/pipeline", pipelineService{commonHandlerData: c, client: gitlabClient}.handler)
	m.HandleFunc("/pipeline/trigger/", pipelineService{commonHandlerData: c, client: gitlabClient}.handler)
	m.HandleFunc("/users/me", meService{commonHandlerData: c, client: gitlabClient}.handler)
	m.HandleFunc("/attachment", attachmentService{commonHandlerData: c, fileReader: attachmentReader{}}.handler)
	m.HandleFunc("/create_mr", mergeRequestCreatorService{commonHandlerData: c, client: gitlabClient}.handler)
	m.HandleFunc("/job", traceFileService{commonHandlerData: c, client: gitlabClient}.handler)
	m.HandleFunc("/project/members", projectListerService{commonHandlerData: c, client: gitlabClient}.handler)
	m.HandleFunc("/merge_requests", mergeRequestListerService{commonHandlerData: c, client: gitlabClient}.handler)

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
func withMr(next http.HandlerFunc, c commonHandlerData, client MergeRequestLister) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// If the merge request is already attached, skip the middleware logic
		if c.projectInfo.MergeId == 0 {
			options := gitlab.ListProjectMergeRequestsOptions{
				Scope:        gitlab.Ptr("all"),
				State:        gitlab.Ptr("opened"),
				SourceBranch: &c.gitInfo.BranchName,
			}

			mergeRequests, _, err := client.ListProjectMergeRequests(c.projectInfo.ProjectId, &options)
			if err != nil {
				handleError(w, fmt.Errorf("Failed to list merge requests: %w", err), "Failed to list merge requests", http.StatusInternalServerError)
				return
			}

			if len(mergeRequests) == 0 {
				err := fmt.Errorf("No merge requests found for branch '%s'", c.gitInfo.BranchName)
				handleError(w, err, "No merge requests found", http.StatusBadRequest)
				return
			}

			mergeIdInt := mergeRequests[0].IID
			c.projectInfo.MergeId = mergeIdInt
		}

		// Call the next handler if middleware succeeds
		next(w, r)
	}
}
