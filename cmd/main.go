package main

import (
	"log"
	"os"

	"gitlab.com/harrisoncramer/gitlab.nvim/cmd/commands"
)

func usage() {
	log.Fatalf("Usage: gitlab-nvim <command>")
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}

	command := os.Args[1]

	switch command {
	case "projectInfo":
		commands.GetProjectInfo()
	case "comment":
		if len(os.Args) < 6 {
			usage()
		}
		projectId, lineNumber, fileName, comment := os.Args[2], os.Args[3], os.Args[4], os.Args[5]
		if lineNumber == "" || fileName == "" || comment == "" || projectId == "" {
			usage()
		}
		project := commands.GetProjectInfo()
		commands.MakeComment(project.ID, lineNumber, fileName, comment)
	case "approve":
		commands.Approve()
	default:
		usage()
	}
}
