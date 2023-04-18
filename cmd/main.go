package main

import (
	"fmt"
	"os"
)

const (
	STAR          = "star"
	SUMMARY       = "summary"
	APPROVE       = "approve"
	REVOKE        = "revoke"
	COMMENT       = "comment"
	LIST_COMMENTS = "listComments"
)

func main() {

	var c Client
	errCheck(c.Init())

	switch c.command {
	case STAR:
		errCheck(c.Star())
	case APPROVE:
		errCheck(c.Approve())
		// case SUMMARY:
		// 	commands.Summary(c.projectId)
		// case REVOKE:
		// 	commands.Revoke(c.projectId)
		// case COMMENT:
		// 	if len(os.Args) < 6 {
		// 		c.Usage()
		// 	}
		// 	lineNumber, fileName, comment := os.Args[3], os.Args[4], os.Args[5]
		// 	if lineNumber == "" || fileName == "" || comment == "" {
		// 		c.Usage()
		// 	}
		// 	commands.MakeComment(c.projectId, lineNumber, fileName, comment)
		// case LIST_COMMENTS:
		// 	commands.ListComments(c.projectId)
		// default:
		// 	c.Usage()
	}
}

func errCheck(err error) {
	if err != nil {
		fmt.Printf("Failure: %v", err)
		os.Exit(1)
	}
}
