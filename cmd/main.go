package main

import (
	"fmt"
	"os"
)

func usage() {
	fmt.Println("Usage: gitlab-nvim <project-id> <line-number> <comment>")
	os.Exit(1)
}

func main() {
	if len(os.Args) < 4 {
		usage()
	}

	projectId, lineNumber, comment := os.Args[1], os.Args[2], os.Args[3]

	if projectId == "" || lineNumber == "" || comment == "" {
		usage()
	}

	fmt.Println("Project ID is: ", projectId)
	fmt.Println("Current Line number is: ", lineNumber)
	fmt.Println("Comment is: ", comment)

}
