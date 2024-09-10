package app

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/xanzy/go-gitlab"
)

// Wraps a series of middleware around the base handler.
// The middlewares should call the serveHTTP method on their http.Handler argument to pass along the request.
func middleware(h http.Handler, middlewares ...func(http.Handler) http.Handler) http.HandlerFunc {
	for _, middleware := range middlewares {
		h = middleware(h)
	}
	return h.ServeHTTP
}

// Logs the request to the Go server, if enabled
func logMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if pluginOptions.Debug.Request {
			logRequest(r)
		}
		next.ServeHTTP(w, r) // Call the ServeHTTP on the next function in the chain
	})
}

/* Gets the current merge request ID and attaches it to the projectInfo */
func withMr(next http.Handler, c data, client MergeRequestLister) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// If the merge request is already attached, skip the middleware logic
		if c.projectInfo.MergeId == 0 {
			options := gitlab.ListProjectMergeRequestsOptions{
				Scope:        gitlab.Ptr("all"),
				SourceBranch: &c.gitInfo.BranchName,
				TargetBranch: pluginOptions.ChosenTargetBranch,
			}

			mergeRequests, _, err := client.ListProjectMergeRequests(c.projectInfo.ProjectId, &options)
			if err != nil {
				handleError(w, fmt.Errorf("Failed to list merge requests: %w", err), "Failed to list merge requests", http.StatusInternalServerError)
				return
			}

			if len(mergeRequests) == 0 {
				err := fmt.Errorf("No merge requests found for branch '%s'", c.gitInfo.BranchName)
				handleError(w, err, "No merge requests found", http.StatusBadRequest)
				return
			}

			if len(mergeRequests) > 1 {
				err := errors.New("Please call gitlab.choose_merge_request()")
				handleError(w, err, "Multiple MRs found", http.StatusBadRequest)
				return
			}

			mergeIdInt := mergeRequests[0].IID
			c.projectInfo.MergeId = mergeIdInt
		}

		// Call the next handler if middleware succeeds
		next.ServeHTTP(w, r)
	})
}
