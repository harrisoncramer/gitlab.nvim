package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
)

type ResponseError struct {
	message string
}

func withGitlabContext(next http.HandlerFunc, c Client) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := context.WithValue(context.Background(), "client", c)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func main() {
	branchName, err := getCurrentBranch()

  if err != nil {
    log.Fatalf("Failure: Failed to get current branch: %v", err)
  }

	if branchName == "main" || branchName == "master" {
		log.Fatalf("Cannot run on %s branch", branchName)
	}

	/* Initialize Gitlab client */
	var c Client

  if err := c.Init(branchName); err != nil {
    log.Fatalf("Failure: Failed to iniialize client: %v", err)
  }

  if err := executeCommand(c); err != nil {
    log.Fatalf("Failure: Command execution failed: %v", err)
  }
  
  m := http.NewServeMux()
	m.Handle("/approve", withGitlabContext(http.HandlerFunc(ApproveHandler), c))
	m.Handle("/revoke", withGitlabContext(http.HandlerFunc(RevokeHandler), c))
	m.Handle("/star", withGitlabContext(http.HandlerFunc(StarHandler), c))
	m.Handle("/info", withGitlabContext(http.HandlerFunc(InfoHandler), c))
	m.Handle("/discussions", withGitlabContext(http.HandlerFunc(ListDiscussionsHandler), c))
	m.Handle("/comment", withGitlabContext(http.HandlerFunc(CommentHandler), c))
	m.Handle("/reply", withGitlabContext(http.HandlerFunc(ReplyHandler), c))

	server := &http.Server{
		Addr:    fmt.Sprintf(":%s", os.Args[2]),
		Handler: m,
	}

	done := make(chan bool)
	go server.ListenAndServe()

	/* This print is detected by the Lua code and used to fetch project information */
	fmt.Println("Server started.")

	<-done
}

func executeCommand(c Client) error {
	switch c.command {
	case star:
		return c.Star()
	case approve:
		return c.Approve()
	case revoke:
		return c.Revoke()
	case comment:
		return c.Comment()
	case deleteComment:
		return c.DeleteComment()
	case editComment:
		return c.EditComment()
	case overviewComment:
		return c.OverviewComment()
	case info:
		return c.Info()
	case reply:
		return c.Reply()
	case listDiscussions:
		return c.ListDiscussions()
	default:
		c.Usage("command")
        return nil
  }
}

/* Gets the current branch */
func getCurrentBranch() (res string, e error) {
	gitCmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")

	output, err := gitCmd.Output()
	if err != nil {
		return "", fmt.Errorf("Error running git rev-parse: %w", err)
	}

	return strings.TrimSpace(string(output)), nil
}
