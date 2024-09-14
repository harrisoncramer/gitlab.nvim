package app

import (
	"fmt"
)

type ErrorResponse struct {
	Message string `json:"message"`
	Details string `json:"details"`
}

type SuccessResponse struct {
	Message string `json:"message"`
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
