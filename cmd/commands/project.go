package commands

import (
	"fmt"
	"os/exec"
)

type Project struct {
}

/* Returns metadata about the current project */
func ProjectInfo() {
	cmd := exec.Command("bash -c", "basename \"$(git rev-parse --show-toplevel)\" ")
	output, err := cmd.Output()
	if err != nil {
		fmt.Println("Error running git rev-parse:", err)
	}

	fmt.Println(output)
}
