package app

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/harrisoncramer/gitlab.nvim/cmd/app/git"
	gitlab "gitlab.com/gitlab-org/api/client-go"
)

type fakeGraphQLClient struct {
	err      error
	jsonData []byte
}

func (f fakeGraphQLClient) Do(query gitlab.GraphQLQuery, response any, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	if f.err != nil {
		return nil, f.err
	}

	// Actually unmarshal JSON into the response struct
	if err := json.Unmarshal(f.jsonData, response); err != nil {
		return nil, err
	}

	// if resp, ok := response.(mergeabilityChecksGraphQLResponse); ok {
	// 	resp.Data.Project.MergeRequest.MergeabilityChecks = f.checks
	// }

	return makeResponse(http.StatusOK), nil
}

var testMergeabilityData = data{
	projectInfo: &ProjectInfo{MergeId: 123},
	gitInfo: &git.GitData{
		BranchName:  "feature-branch",
		Namespace:   "test-namespace",
		ProjectName: "test-project",
	},
}

func TestMergeabilityChecksHandler(t *testing.T) {
	t.Run("Returns mergeability checks", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/mergeability_checks", nil)
		client := fakeGraphQLClient{
			jsonData: []byte(`{
				"data": {
					"project": {
						"mergeRequest": {
							"mergeabilityChecks": [
								{"identifier": "CI_MUST_PASS", "status": "SUCCESS"},
								{"identifier": "CONFLICT", "status": "FAILED"}
							]
						}
					}
				}
			}`),
		}
		svc := middleware(
			mergeabilityChecksService{testMergeabilityData, client},
			withMethodCheck(http.MethodGet),
		)

		res := httptest.NewRecorder()
		svc.ServeHTTP(res, request)

		var data MergeabilityChecksResponse
		err := json.Unmarshal(res.Body.Bytes(), &data)
		assert(t, err, nil)

		assert(t, data.Message, "Mergeability checks retrieved")
		assert(t, len(data.MergeabilityChecks), 2)
		assert(t, data.MergeabilityChecks[0].Identifier, "CI_MUST_PASS")
		assert(t, data.MergeabilityChecks[0].Status, "SUCCESS")
		assert(t, data.MergeabilityChecks[1].Identifier, "CONFLICT")
		assert(t, data.MergeabilityChecks[1].Status, "FAILED")
	})

	t.Run("Returns empty list when there are no checks", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/mergeability_checks", nil)
		client := fakeGraphQLClient{
			jsonData: []byte(`{
				"data": {
					"project": {
						"mergeRequest": {
							"mergeabilityChecks": []
						}
					}
				}
			}`),
		}
		svc := middleware(
			mergeabilityChecksService{testMergeabilityData, client},
			withMethodCheck(http.MethodGet),
		)

		res := httptest.NewRecorder()
		svc.ServeHTTP(res, request)

		var data MergeabilityChecksResponse
		err := json.Unmarshal(res.Body.Bytes(), &data)
		assert(t, err, nil)

		assert(t, data.Message, "Mergeability checks retrieved")
		assert(t, len(data.MergeabilityChecks), 0)
	})

	t.Run("Handles errors from Gitlab client", func(t *testing.T) {
		request := makeRequest(t, http.MethodGet, "/mr/mergeability_checks", nil)
		client := fakeGraphQLClient{err: errorFromGitlab}
		svc := middleware(
			mergeabilityChecksService{testMergeabilityData, client},
			withMethodCheck(http.MethodGet),
		)
		data, _ := getFailData(t, svc, request)
		assert(t, data.Message, "Could not get mergeability checks")
		assert(t, data.Error, "failed to fetch mergeability checks: "+errorFromGitlab.Error())
	})
}
