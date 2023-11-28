package main

import (
	"log"
)

func main() {
	gitInfo, err := extractGitInfo(RefreshProjectInfo, GetProjectUrlFromNativeGitCmd, GetCurrentBranchNameFromNativeGitCmd)
	if err != nil {
		log.Fatalf("Failure initializing plugin with `git` commands: %v", err)
	}

	err, client := initGitlabClient()
	if err != nil {
		log.Fatalf("Failed to initialize Gitlab client: %v", err)
	}

	err, projectInfo := initProjectSettings(client, gitInfo)
	if err != nil {
		log.Fatalf("Failed to initialize project settings: %v", err)
	}

	m := createServer(client, projectInfo, attachmentReader{})
	startServer(m)
}
