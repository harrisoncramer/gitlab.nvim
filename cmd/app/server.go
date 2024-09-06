package app

import (
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/harrisoncramer/gitlab.nvim/cmd/app/git"
	"github.com/xanzy/go-gitlab"
)

/*
startSever starts the server and runs concurrent goroutines
to handle potential shutdown requests and incoming HTTP requests.
*/
func StartServer(client *Client, projectInfo *ProjectInfo, GitInfo git.GitData) {

	s := shutdown{
		sigCh: make(chan os.Signal, 1),
	}

	fr := attachmentReader{}
	r := CreateRouter(
		client,
		projectInfo,
		s,
		func(a *data) error { a.projectInfo = projectInfo; return nil },
		func(a *data) error { a.gitInfo = &GitInfo; return nil },
		func(a *data) error { err := attachEmojis(a, fr); return err },
	)
	l := createListener()

	server := &http.Server{Handler: r}

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
CreateRouterAndApi wires up the router and attaches all handlers to their respective routes. It also
iterates over all option functions to configure API fields such as the project information and default
file reader functionality
*/

type data struct {
	projectInfo *ProjectInfo
	gitInfo     *git.GitData
	emojiMap    EmojiMap
}

type optFunc func(a *data) error

func CreateRouter(gitlabClient *Client, projectInfo *ProjectInfo, s ShutdownHandler, optFuncs ...optFunc) *http.ServeMux {
	m := http.NewServeMux()

	d := data{
		projectInfo: &ProjectInfo{},
		gitInfo:     &git.GitData{},
	}

	/* Mutates the API struct as necessary with configuration functions */
	for _, optFunc := range optFuncs {
		err := optFunc(&d)
		if err != nil {
			panic(err)
		}
	}

	m.HandleFunc("/mr/approve", withMr(mergeRequestApproverService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/comment", withMr(commentService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/merge", withMr(mergeRequestAccepterService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/discussions/list", withMr(discussionsListerService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/discussions/resolve", withMr(discussionsResolutionService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/info", withMr(infoService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/assignee", withMr(assigneesService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/summary", withMr(summaryService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/reviewer", withMr(reviewerService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/revisions", withMr(revisionsService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/reply", withMr(replyService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/label", withMr(labelService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/revoke", withMr(mergeRequestRevokerService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/awardable/note/", withMr(emojiService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/draft_notes/", withMr(draftNoteService{d, gitlabClient}, d, gitlabClient))
	m.HandleFunc("/mr/draft_notes/publish", withMr(draftNotePublisherService{d, gitlabClient}, d, gitlabClient))

	m.HandleFunc("/pipeline", pipelineService{d, gitlabClient, git.Git{}}.handler)
	m.HandleFunc("/pipeline/trigger/", pipelineService{d, gitlabClient, git.Git{}}.handler)
	m.HandleFunc("/users/me", meService{d, gitlabClient}.handler)
	m.HandleFunc("/attachment", attachmentService{data: d, client: gitlabClient, fileReader: attachmentReader{}}.handler)
	m.HandleFunc("/create_mr", mergeRequestCreatorService{d, gitlabClient}.handler)
	m.HandleFunc("/job", traceFileService{d, gitlabClient}.handler)
	m.HandleFunc("/project/members", projectMemberService{d, gitlabClient}.handler)
	m.HandleFunc("/merge_requests", mergeRequestListerService{d, gitlabClient}.handler)

	m.HandleFunc("/shutdown", s.shutdownHandler)
	m.Handle("/ping", http.HandlerFunc(pingHandler))

	return m
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

type ServiceWithHandler interface {
	handler(http.ResponseWriter, *http.Request)
}

/* withMr is a Middlware that gets the current merge request ID and attaches it to the projectInfo */
func withMr(svc ServiceWithHandler, c data, client MergeRequestLister) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// If the merge request is already attached, skip the middleware logic
		if c.projectInfo.MergeId == 0 {
			options := gitlab.ListProjectMergeRequestsOptions{
				Scope:        gitlab.Ptr("all"),
				State:        gitlab.Ptr("opened"),
				SourceBranch: &c.gitInfo.BranchName,
				TargetBranch: pluginOptions.ChosenTargetBranch,
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

			if len(mergeRequests) > 1 {
				err := errors.New("Please call gitlab.choose_merge_request()")
				handleError(w, err, "Multiple MRs found", http.StatusBadRequest)
				return
			}

			mergeIdInt := mergeRequests[0].IID
			c.projectInfo.MergeId = mergeIdInt
		}

		// Call the next handler if middleware succeeds
		svc.handler(w, r)
	}
}
