package mock_main

import (
	"testing"

	gitlab "github.com/xanzy/go-gitlab"
	gomock "go.uber.org/mock/gomock"
)

type NoOp = []gitlab.RequestOptionFunc

func NewMockObj(t *testing.T) *MockClientInterface {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()
	mockObj := NewMockClientInterface(ctrl)
	return mockObj
}
