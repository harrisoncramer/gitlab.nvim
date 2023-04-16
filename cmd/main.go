package main

import (
	"log"
	"os"

	"gitlab.com/harrisoncramer/gitlab.nvim/cmd/commands"
)

const (
	INFO    = "projectInfo"
	APPROVE = "approve"
	REVOKE  = "revoke"
	COMMENT = "comment"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}

	command := os.Args[1]

	switch command {
	case INFO:
		commands.GetProjectInfo()
	case APPROVE:
		projectId := os.Args[2]
		if projectId == "" {
			usage()
		}
		commands.Approve(projectId)
	case REVOKE:
		projectId := os.Args[2]
		if projectId == "" {
			usage()
		}
		commands.Revoke(projectId)
	case COMMENT:
		if len(os.Args) < 6 {
			usage()
		}
		projectId, lineNumber, fileName, comment := os.Args[2], os.Args[3], os.Args[4], os.Args[5]
		if lineNumber == "" || fileName == "" || comment == "" || projectId == "" {
			usage()
		}
		commands.MakeComment(projectId, lineNumber, fileName, comment)
	default:
		usage()
	}
}

func usage() {
	log.Fatalf("Usage: gitlab-nvim <command> <args>")
}
