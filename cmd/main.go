package main

import (
	"fmt"
	"os"

	"gitlab.com/harrisoncramer/gitlab.nvim/cmd/commands"
)

func usage() {
	fmt.Println("Usage: gitlab-nvim <command>")
	os.Exit(1)
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}

	command := os.Args[1]

	switch command {
	case "projectInfo":
		project := commands.GetProjectInfo()
		fmt.Println(project)
		os.Exit(0)
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
	default:
		usage()
	}
}
