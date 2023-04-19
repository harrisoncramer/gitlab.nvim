package main

import (
	"log"
	"os"
)

const (
	STAR    = "star"
	INFO    = "info"
	APPROVE = "approve"
	REVOKE  = "revoke"
	COMMENT = "comment"
	// LIST_COMMENTS = "listComments"
)

func main() {

	var c Client
	errCheck(c.Init())

	switch c.command {
	case STAR:
		errCheck(c.Star())
	case APPROVE:
		errCheck(c.Approve())
	case REVOKE:
		errCheck(c.Revoke())
	case COMMENT:
		errCheck(c.Comment())
	case INFO:
		errCheck(c.Info())
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
		log.Fatalf("Failure: %s", err)
		os.Exit(1)
	}
}
