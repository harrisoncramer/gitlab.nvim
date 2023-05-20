package main

import (
	"fmt"
	"os"
)

func (c *Client) Start() error {
	processId := os.Getpid()
	fmt.Println(processId)
	return nil
}
