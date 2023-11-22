package main

import (
	"log"
)

func main() {
	gitInfo, err := ExtractGitInfo(RefreshProjectInfo, GetProjectUrlFromNativeGitCmd, GetCurrentBranchNameFromNativeGitCmd)
	if err != nil {
		log.Fatalf("Failure initializing plugin with `git` commands: %v", err)
	}

	err, client := InitGitlabClient()
	if err != nil {
		log.Fatalf("Failed to initialize Gitlab client: %v", err)
	}

	err, projectInfo := InitProjectSettings(client, gitInfo)
	if err != nil {
		log.Fatalf("Failed to initialize project settings: %v", err)
	}

	StartServer(client, projectInfo)

}
