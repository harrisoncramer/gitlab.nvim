package app

import (
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/harrisoncramer/gitlab.nvim/cmd/app/git"
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

	m.HandleFunc("/mr/approve", middleware(
		withMr(mergeRequestApproverService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/comment", middleware(
		withMr(commentService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/merge", middleware(
		withMr(mergeRequestAccepterService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/discussions/list", middleware(
		withMr(discussionsListerService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/discussions/resolve", middleware(
		withMr(discussionsResolutionService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/info", middleware(
		withMr(infoService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/assignee", middleware(
		withMr(assigneesService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/summary", middleware(
		withMr(summaryService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/reviewer", middleware(
		withMr(reviewerService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/revisions", middleware(
		withMr(revisionsService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/reply", middleware(
		withMr(replyService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/label", middleware(
		withMr(labelService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/revoke", middleware(
		withMr(mergeRequestRevokerService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/awardable/note/", middleware(
		withMr(emojiService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/draft_notes/", middleware(
		withMr(draftNoteService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/mr/draft_notes/publish", middleware(
		withMr(draftNotePublisherService{d, gitlabClient}, d, gitlabClient),
		logMiddleware,
	))
	m.HandleFunc("/pipeline", middleware(
		pipelineService{d, gitlabClient, git.Git{}},
		logMiddleware,
	))
	m.HandleFunc("/pipeline/trigger/", middleware(
		pipelineService{d, gitlabClient, git.Git{}},
		logMiddleware,
	))
	m.HandleFunc("/users/me", middleware(
		meService{d, gitlabClient},
		logMiddleware,
	))
	m.HandleFunc("/attachment", middleware(
		attachmentService{data: d, client: gitlabClient, fileReader: attachmentReader{}},
		logMiddleware,
	))
	m.HandleFunc("/create_mr", middleware(
		mergeRequestCreatorService{d, gitlabClient},
		logMiddleware,
	))
	m.HandleFunc("/job", middleware(
		traceFileService{d, gitlabClient},
		logMiddleware,
	))
	m.HandleFunc("/project/members", middleware(
		projectMemberService{d, gitlabClient},
		logMiddleware,
	))
	m.HandleFunc("/merge_requests", middleware(
		mergeRequestListerService{d, gitlabClient},
		logMiddleware,
	))
	m.HandleFunc("/merge_requests_by_username", middleware(
		mergeRequestListerByUsernameService{d, gitlabClient},
		logMiddleware,
	))

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
