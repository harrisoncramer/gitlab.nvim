package main

import (
	"fmt"
	"os"
)

func usage() {
	fmt.Println("Usage: gitlab-nvim <merge-request-id> <line-number> <comment>")
	os.Exit(1)
}

func main() {
	if len(os.Args) < 4 {
		usage()
	}

	mergeId, lineId, comment := os.Args[1], os.Args[2], os.Args[3]

	if mergeId == "" || lineId == "" || comment == "" {
		usage()
	}
}
