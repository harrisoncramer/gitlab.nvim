package main

import (
	"fmt"
	"sort"

	"encoding/json"

	"github.com/xanzy/go-gitlab"
)

type SortableDiscussions []*gitlab.Discussion

func (n SortableDiscussions) Len() int {
	return len(n)
}

func (d SortableDiscussions) Less(i int, j int) bool {
	iTime := d[i].Notes[len(d[i].Notes)-1].CreatedAt
	jTime := d[j].Notes[len(d[j].Notes)-1].CreatedAt
	return iTime.After(*jTime)

}

func (n SortableDiscussions) Swap(i, j int) {
	n[i], n[j] = n[j], n[i]
}

func (c *Client) ListDiscussions() error {

	mergeRequestDiscussionOptions := gitlab.ListMergeRequestDiscussionsOptions{
		Page:    1,
		PerPage: 250,
	}
	discussions, _, err := c.git.Discussions.ListMergeRequestDiscussions(c.projectId, c.mergeId, &mergeRequestDiscussionOptions, nil)

	if err != nil {
		return fmt.Errorf("Listing discussions failed: %w", err)
	}

	var realDiscussions []*gitlab.Discussion
	for i := 0; i < len(discussions); i++ {
		notes := discussions[i].Notes
		for j := 0; j < len(notes); j++ {
			if notes[j].Type == gitlab.NoteTypeValue("DiffNote") {
				realDiscussions = append(realDiscussions, discussions[i])
				break
			}
		}
	}

	sortedDiscussions := SortableDiscussions(realDiscussions)
	sort.Sort(sortedDiscussions)

	discussionsOutput, err := json.Marshal(sortedDiscussions)

	fmt.Println(string(discussionsOutput))

	return nil
}
