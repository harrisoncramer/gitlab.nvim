package main

import (
	"encoding/json"
	"log"
	"os"

	"gitlab.com/harrisoncramer/gitlab.nvim/cmd/app"
	"gitlab.com/harrisoncramer/gitlab.nvim/cmd/app/git"
)

var pluginOptions app.PluginOptions

func main() {
	log.SetFlags(0)

	err := json.Unmarshal([]byte(os.Args[1]), &pluginOptions)
	app.SetPluginOptions(pluginOptions)

	if err != nil {
		log.Fatalf("Failure parsing plugin settings: %v", err)
	}

	gitManager := git.Git{}
	gitData, err := git.NewGitData(pluginOptions.ConnectionSettings.Remote, gitManager)

	if err != nil {
		log.Fatalf("Failure initializing plugin: %v", err)
	}

	err, client := app.NewClient()
	if err != nil {
		log.Fatalf("Failed to initialize Gitlab client: %v", err)
	}

	err, projectInfo := app.InitProjectSettings(client, gitData)
	if err != nil {
		log.Fatalf("Failed to initialize project settings: %v", err)
	}

	app.StartServer(client, projectInfo, gitData)
}
