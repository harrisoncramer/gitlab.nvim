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

func main() {

	branchName, err := getCurrentBranch()
	errCheck(err)
	if branchName == "main" || branchName == "master" {
		log.Fatalf("Cannot run on %s branch", branchName)
	}

	/* Initialize Gitlab client */
	var c Client
	errCheck(c.Init(branchName))

	/* TODO: Check method types */
	m := http.NewServeMux()
	m.Handle("/approve", withGitlabContext(http.HandlerFunc(ApproveHandler), c))
	m.Handle("/revoke", withGitlabContext(http.HandlerFunc(RevokeHandler), c))
	m.Handle("/star", withGitlabContext(http.HandlerFunc(StarHandler), c))
	m.Handle("/info", withGitlabContext(http.HandlerFunc(InfoHandler), c))
	m.Handle("/discussions", withGitlabContext(http.HandlerFunc(ListDiscussionsHandler), c))
	m.Handle("/comment", withGitlabContext(http.HandlerFunc(PostCommentHandler), c))

	http.ListenAndServe(":8081", m)

	// switch c.command {
	// case deleteComment:
	// 	errCheck(c.DeleteComment())
	// case editComment:
	// 	errCheck(c.EditComment())
	// case overviewComment:
	// 	errCheck(c.OverviewComment())
	// case reply:
	// 	errCheck(c.Reply())
	// default:
	// 	c.Usage("command")
	// }
}

type ResponseError struct {
	message string
}

func withGitlabContext(next http.HandlerFunc, c Client) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := context.WithValue(context.Background(), "client", c)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func errCheck(err error) {
	if err != nil {
		log.Fatalf("Failure: %s", err)
		os.Exit(1)
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
