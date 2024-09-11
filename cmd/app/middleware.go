package app

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/go-playground/validator/v10"
	"github.com/xanzy/go-gitlab"
)

type mw func(http.Handler) http.Handler

// Wraps a series of middleware around the base handler.
// The middlewares should call the serveHTTP method on their http.Handler argument to pass along the request.
func middleware(h http.Handler, middlewares ...mw) http.HandlerFunc {
	for _, middleware := range middlewares {
		h = middleware(h)
	}
	return h.ServeHTTP
}

var validate = validator.New()

type methodToPayload map[string]any

type validatorMiddleware struct {
	validate        *validator.Validate
	methodToPayload methodToPayload
}

func (p validatorMiddleware) handle(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			handleError(w, err, "Could not read request body", http.StatusBadRequest)
			return
		}

		payload := p.methodToPayload[r.Method]
		err = json.Unmarshal(body, &payload)

		if err != nil {
			handleError(w, err, "Could not parse JSON request body", http.StatusBadRequest)
			return
		}

		err = p.validate.Struct(payload)
		if err != nil {
			switch err := err.(type) {
			case validator.ValidationErrors:
				handleError(w, formatValidationErrors(err), "Invalid payload", http.StatusBadRequest)
				return
			case *validator.InvalidValidationError:
				handleError(w, err, "Invalid validation error", http.StatusInternalServerError)
				return
			}
		}

		// Pass the parsed data so we don't have to re-parse it in the handler
		ctx := context.WithValue(r.Context(), "payload", payload)
		r = r.WithContext(ctx)

		next.ServeHTTP(w, r)
	})
}

func validatePayloads(mtp methodToPayload) mw {
	return validatorMiddleware{validate: validate, methodToPayload: mtp}.handle
}

// Logs the request to the Go server, if enabled
func logMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
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

type methodMiddleware struct {
	validate *validator.Validate
	methods  []string
}

func (m methodMiddleware) handle(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		method := r.Method
		for _, acceptableMethod := range m.methods {
			if method == acceptableMethod {
				next.ServeHTTP(w, r)
				return
			}
		}

		w.Header().Set("Access-Control-Allow-Methods", http.MethodPut)
		handleError(w, InvalidRequestError{fmt.Sprintf("Expected: %s", strings.Join(m.methods, "; "))}, "Invalid request type", http.StatusMethodNotAllowed)
	})
}

func validateMethods(methods ...string) mw {
	return methodMiddleware{
		methods: methods,
	}.handle
}

// Helper function to format validation errors into more readable strings
func formatValidationErrors(errors validator.ValidationErrors) error {
	var s strings.Builder
	for i, e := range errors {
		if i > 0 {
			s.WriteString("; ")
		}
		switch e.Tag() {
		case "required":
			s.WriteString(fmt.Sprintf("%s is required", e.Field()))
		default:
			s.WriteString(fmt.Sprintf("The field '%s' failed on validation on the '%s' tag", e.Field(), e.Tag()))
		}
	}

	return fmt.Errorf(s.String())
}
