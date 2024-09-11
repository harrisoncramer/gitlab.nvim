package app

import (
	"fmt"
)

type ErrorResponse struct {
	Message string `json:"message"`
	Details string `json:"details"`
	Status  int    `json:"status"`
}

type SuccessResponse struct {
	Message string `json:"message"`
	Status  int    `json:"status"`
}

type GenericError struct {
	endpoint string
}

func (e GenericError) Error() string {
	return fmt.Sprintf("An error occurred on the %s endpoint", e.endpoint)
}

type InvalidRequestError struct{ msg string }

func (e InvalidRequestError) Error() string {
	return e.msg
}
