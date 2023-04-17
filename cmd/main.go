package main

import (
	"log"
	"os"

	"gitlab.com/harrisoncramer/gitlab.nvim/cmd/commands"
)

const (
	INFO          = "projectInfo"
	SUMMARY       = "summary"
	APPROVE       = "approve"
	REVOKE        = "revoke"
	COMMENT       = "comment"
	LIST_COMMENTS = "listComments"
)

func main() {
	if len(os.Args) < 3 {
		usage()
	}

	command, projectId := os.Args[1], os.Args[2]

	if projectId == "" {
		usage()
	}

	switch command {
	case INFO:
		commands.GetProjectInfo()
	case APPROVE:
		commands.Approve(projectId)
	case SUMMARY:
		commands.Summary(projectId)
	case REVOKE:
		commands.Revoke(projectId)
	case COMMENT:
		if len(os.Args) < 6 {
			usage()
		}
		lineNumber, fileName, comment := os.Args[3], os.Args[4], os.Args[5]
		if lineNumber == "" || fileName == "" || comment == "" {
			usage()
		}
		commands.MakeComment(projectId, lineNumber, fileName, comment)
	case LIST_COMMENTS:
		commands.ListComments(projectId)
	default:
		usage()
	}
}

func usage() {
	log.Fatalf("Usage: gitlab-nvim <command> <project-id> <args?>")
}
