package main

type Comment struct {
	View                    string `json:"view"`
	LineType                string `json:"line_type"`
	MergeRequestDiffHeadSha string `json:"merge_request_diff_head_sha"`
	InReplyToDiscussionId   string `json:"in_reply_to_discussion_id"`
	NoteProjectId           string `json:"note_project_id"`
	TargetType              string `json:"target_type"`
	TargetId                int    `json:"target_id"`
	ReturnDiscussion        bool   `json:"return_discussion"`
	Note                    struct {
		Note         string `json:"note"`
		Position     string `json:"position"`
		NoteableType string `json:"noteable_type"`
		NoteableId   int    `json:"noteable_id"`
		CommitId     int    `json:"commit_id"`
		Type         string `json:"type"`
		LineCode     string `json:"line_code"`
	}
}
