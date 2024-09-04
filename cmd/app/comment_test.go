package app

import (
	"net/http"
	"testing"

	"github.com/xanzy/go-gitlab"
)

type fakeCommentClient struct {
	testBase
}

func (f fakeCommentClient) CreateMergeRequestDiscussion(pid interface{}, mergeRequest int, opt *gitlab.CreateMergeRequestDiscussionOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Discussion, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	return &gitlab.Discussion{Notes: []*gitlab.Note{{}}}, resp, err
}
func (f fakeCommentClient) UpdateMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, note int, opt *gitlab.UpdateMergeRequestDiscussionNoteOptions, options ...gitlab.RequestOptionFunc) (*gitlab.Note, *gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, nil, err
	}

	return &gitlab.Note{}, resp, err
}

func (f fakeCommentClient) DeleteMergeRequestDiscussionNote(pid interface{}, mergeRequest int, discussion string, note int, options ...gitlab.RequestOptionFunc) (*gitlab.Response, error) {
	resp, err := f.handleGitlabError()
	if err != nil {
		return nil, err
	}
	return resp, err
}

// var testCommentDeletionData = DeleteCommentRequest{NoteId: 3, DiscussionId: "abc123"}
// var testEditCommentData = EditCommentRequest{Comment: "Some comment", NoteId: 3, DiscussionId: "abc123"}
func TestPostComment(t *testing.T) {
	var testCommentCreationData = PostCommentRequest{Comment: "Some comment"}
	t.Run("Creates a new note (unlinked comment)", func(t *testing.T) {
		request := makeRequest(t, http.MethodPost, "/mr/comment", testCommentCreationData)
		svc := commentService{emptyProjectData, fakeCommentClient{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Comment created successfully")
		assert(t, data.Status, http.StatusOK)
	})

	t.Run("Creates a new comment", func(t *testing.T) {
		testCommentCreationData := PostCommentRequest{ // Re-create comment creation data to avoid mutating this variable in other tests
			Comment: "Some comment",
			PositionData: PositionData{
				FileName: "file.txt",
			},
		}
		request := makeRequest(t, http.MethodPost, "/mr/comment", testCommentCreationData)
		svc := commentService{emptyProjectData, fakeCommentClient{}}
		data := getSuccessData(t, svc, request)
		assert(t, data.Message, "Comment created successfully")
		assert(t, data.Status, http.StatusOK)
	})

	//		t.Run("Handles errors from Gitlab client", func(t *testing.T) {
	//			client := mock_main.NewMockClient(t)
	//			mock_main.WithMr(t, client)
	//			client.EXPECT().CreateMergeRequestDiscussion(
	//				"",
	//				mock_main.MergeId,
	//				gomock.Any(),
	//			).Return(nil, nil, errors.New("Some error from Gitlab"))
	//
	//			request := makeRequest(t, http.MethodPost, "/mr/comment", testCommentCreationData)
	//			server := CreateRouter(client)
	//			data := serveRequest(t, server, request, ErrorResponse{})
	//
	//			checkErrorFromGitlab(t, *data, "Could not create discussion")
	//		})
	//
	//		t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
	//			client := mock_main.NewMockClient(t)
	//			mock_main.WithMr(t, client)
	//			client.EXPECT().CreateMergeRequestDiscussion(
	//				"",
	//				mock_main.MergeId,
	//				gomock.Any(),
	//			).Return(nil, makeResponse(http.StatusSeeOther), nil)
	//
	//			request := makeRequest(t, http.MethodPost, "/mr/comment", testCommentCreationData)
	//			server := CreateRouter(client)
	//			data := serveRequest(t, server, request, ErrorResponse{})
	//
	//			checkNon200(t, *data, "Could not create discussion", "/mr/comment")
	//		})
	//	}
	//
	//	func TestDeleteComment(t *testing.T) {
	//		t.Run("Deletes a comment", func(t *testing.T) {
	//			client := mock_main.NewMockClient(t)
	//			mock_main.WithMr(t, client)
	//			client.EXPECT().DeleteMergeRequestDiscussionNote("", mock_main.MergeId, testCommentDeletionData.DiscussionId, testCommentDeletionData.NoteId).Return(makeResponse(http.StatusOK), nil)
	//
	//			request := makeRequest(t, http.MethodDelete, "/mr/comment", testCommentDeletionData)
	//			server := CreateRouter(client)
	//			data := serveRequest(t, server, request, CommentResponse{})
	//
	//			assert(t, data.SuccessResponse.Message, "Comment deleted successfully")
	//			assert(t, data.SuccessResponse.Status, http.StatusOK)
	//		})
	//
	//		t.Run("Handles errors from Gitlab client", func(t *testing.T) {
	//			client := mock_main.NewMockClient(t)
	//			mock_main.WithMr(t, client)
	//			client.EXPECT().DeleteMergeRequestDiscussionNote("", mock_main.MergeId, testCommentDeletionData.DiscussionId, testCommentDeletionData.NoteId).Return(nil, errorFromGitlab)
	//
	//			request := makeRequest(t, http.MethodDelete, "/mr/comment", testCommentDeletionData)
	//			server := CreateRouter(client)
	//			data := serveRequest(t, server, request, ErrorResponse{})
	//
	//			checkErrorFromGitlab(t, *data, "Could not delete comment")
	//		})
	//
	//		t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
	//			client := mock_main.NewMockClient(t)
	//			mock_main.WithMr(t, client)
	//			client.EXPECT().DeleteMergeRequestDiscussionNote("", mock_main.MergeId, testCommentDeletionData.DiscussionId, testCommentDeletionData.NoteId).Return(makeResponse(http.StatusSeeOther), nil)
	//
	//			request := makeRequest(t, http.MethodDelete, "/mr/comment", testCommentDeletionData)
	//			server := CreateRouter(client)
	//			data := serveRequest(t, server, request, ErrorResponse{})
	//
	//			checkNon200(t, *data, "Could not delete comment", "/mr/comment")
	//		})
	//	}
	//
	//	func TestEditComment(t *testing.T) {
	//		t.Run("Edits a comment", func(t *testing.T) {
	//			client := mock_main.NewMockClient(t)
	//			mock_main.WithMr(t, client)
	//			opts := gitlab.UpdateMergeRequestDiscussionNoteOptions{
	//				Body: gitlab.Ptr(testEditCommentData.Comment),
	//			}
	//			client.EXPECT().UpdateMergeRequestDiscussionNote("", mock_main.MergeId, testEditCommentData.DiscussionId, testEditCommentData.NoteId, &opts).Return(&gitlab.Note{}, makeResponse(http.StatusOK), nil)
	//
	//			request := makeRequest(t, http.MethodPatch, "/mr/comment", testEditCommentData)
	//			server := CreateRouter(client)
	//			data := serveRequest(t, server, request, CommentResponse{})
	//
	//			assert(t, data.SuccessResponse.Message, "Comment updated successfully")
	//			assert(t, data.SuccessResponse.Status, http.StatusOK)
	//		})
	//
	//		t.Run("Handles errors from Gitlab client", func(t *testing.T) {
	//			client := mock_main.NewMockClient(t)
	//			mock_main.WithMr(t, client)
	//			client.EXPECT().UpdateMergeRequestDiscussionNote("", mock_main.MergeId, testEditCommentData.DiscussionId, testEditCommentData.NoteId, gomock.Any()).Return(nil, nil, errorFromGitlab)
	//
	//			request := makeRequest(t, http.MethodPatch, "/mr/comment", testEditCommentData)
	//			server := CreateRouter(client)
	//			data := serveRequest(t, server, request, ErrorResponse{})
	//
	//			checkErrorFromGitlab(t, *data, "Could not update comment")
	//		})
	//
	//		t.Run("Handles non-200s from Gitlab", func(t *testing.T) {
	//			client := mock_main.NewMockClient(t)
	//			mock_main.WithMr(t, client)
	//			client.EXPECT().UpdateMergeRequestDiscussionNote("", mock_main.MergeId, testEditCommentData.DiscussionId, testEditCommentData.NoteId, gomock.Any()).Return(nil, makeResponse(http.StatusSeeOther), nil)
	//
	//			request := makeRequest(t, http.MethodPatch, "/mr/comment", testEditCommentData)
	//			server := CreateRouter(client)
	//			data := serveRequest(t, server, request, ErrorResponse{})
	//			checkNon200(t, *data, "Could not update comment", "/mr/comment")
	//		})
}
