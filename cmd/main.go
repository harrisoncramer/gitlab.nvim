package main

import (
	"log"
)

func main() {
	log.SetFlags(0)
	gitInfo, err := extractGitInfo(RefreshProjectInfo, GetProjectUrlFromNativeGitCmd, GetCurrentBranchNameFromNativeGitCmd)
	if err != nil {
		log.Fatalf("Failure initializing plugin: %v", err)
	}

	err, client := initGitlabClient()
	if err != nil {
		log.Fatalf("Failed to initialize Gitlab client: %v", err)
	}

	err, projectInfo := initProjectSettings(client, gitInfo)
	if err != nil {
		log.Fatalf("Failed to initialize project settings: %v", err)
	}

	startServer(client, projectInfo, gitInfo)
}
