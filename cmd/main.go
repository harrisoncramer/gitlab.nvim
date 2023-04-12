package main

import (
	"fmt"
	"os"

	"gitlab.com/harrisoncramer/gitlab.nvim/cmd/commands"
)

func usage() {
	fmt.Println("Usage: gitlab-nvim <project-id> <line-number> <comment>")
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
		fmt.Printf("%+v", project)
		os.Exit(0)
	case "comment":
		project := commands.GetProjectInfo()
		commands.MakeComment(project.ID)
	default:
		usage()
	}

	// if command == "" || projectId == "" || lineNumber == "" || comment == "" {
	// 	usage()
	// }

	// , projectId, lineNumber, comment := os.Args[1], os.Args[2], os.Args[3], os.Args[4]
	// 	fmt.Println("Command is: ", command)
	// 	fmt.Println("Project ID is: ", projectId)
	// 	fmt.Println("Current Line number is: ", lineNumber)
	// 	fmt.Println("Comment is: ", comment)

}
