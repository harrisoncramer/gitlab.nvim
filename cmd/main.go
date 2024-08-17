package main

import (
	"encoding/json"
	"log"
	"os"
)

type PluginOptions struct {
	Insecure  bool   `json:"insecure"`
	GitlabUrl string `json:"gitlab_url"`
	Port      int    `json:"port"`
	AuthToken string `json:"auth_token"`
	LogPath   string `json:"log_path"`
	Debug     struct {
		Request  bool `json:"go_request"`
		Response bool `json:"go_response"`
	} `json:"debug"`
	ConnectionSettings struct {
		Insecure     bool   `json:"insecure"`
		RemoteBranch string `json:"remote_branch"`
	} `json:"connection_settings"`
}

var pluginOptions PluginOptions

func main() {
	log.SetFlags(0)

	err := json.Unmarshal([]byte(os.Args[1]), &pluginOptions)
	if err != nil {
		log.Fatalf("Failure parsing plugin settings: %v", err)
	}

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
