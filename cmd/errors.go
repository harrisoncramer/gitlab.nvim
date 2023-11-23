package main

import "fmt"

type GenericError struct {
	endpoint string
}

func (e GenericError) Error() string {
	return fmt.Sprintf("An error occured on the %s endpoint", e.endpoint)
}
