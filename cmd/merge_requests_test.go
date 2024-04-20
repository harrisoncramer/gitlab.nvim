package main

import (
	"net/http"
	"testing"
)

func TestMergeRequestHandler(t *testing.T) {
	t.Run("Should fetch merge requests", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/merge_requests", nil)
		server, _ := createRouterAndApi(fakeClient{})
		data := serveRequest(t, server, request, ListMergeRequestResponse{})
		assert(t, data.Message, "Merge requests fetched successfully")
		assert(t, data.Status, http.StatusOK)
	})
}
