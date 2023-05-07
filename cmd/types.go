package main

type ErrorResponse struct {
	Message string `json:"message"`
	Status  int    `json:"status"`
}

type SuccessResponse struct {
	Message string `json:"message"`
	Status  int    `json:"status"`
}
