package app

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"strconv"
	"strings"
	"sync"

	"github.com/xanzy/go-gitlab"
)

type Emoji struct {
	Unicode           string   `json:"unicode"`
	UnicodeAlternates []string `json:"unicode_alternates"`
	Name              string   `json:"name"`
	Shortname         string   `json:"shortname"`
	Category          string   `json:"category"`
	Aliases           []string `json:"aliases"`
	AliasesASCII      []string `json:"aliases_ascii"`
	Keywords          []string `json:"keywords"`
	Moji              string   `json:"moji"`
}

type EmojiMap map[string]Emoji

type CreateNoteEmojiPost struct {
	Emoji  string `json:"emoji"`
	NoteId int    `json:"note_id"`
}

type CreateEmojiResponse struct {
	SuccessResponse
	Emoji *gitlab.AwardEmoji
}

/*
attachEmojis reads the emojis from our external JSON file
and attaches them to the data so that they can be looked up later
*/
func attachEmojis(a *data, fr FileReader) error {

	e, err := os.Executable()
	if err != nil {
		return err
	}

	binPath := path.Dir(e)
	filePath := fmt.Sprintf("%s/config/emojis.json", binPath)

	reader, err := fr.ReadFile(filePath)

	if err != nil {
		return fmt.Errorf("Could not find emojis at %s", filePath)
	}

	bytes, err := io.ReadAll(reader)
	if err != nil {
		return errors.New("Could not read emoji file")
	}

	var emojiMap EmojiMap
	err = json.Unmarshal(bytes, &emojiMap)
	if err != nil {
		return errors.New("Could not unmarshal emojis")
	}

	a.emojiMap = emojiMap
	return nil
}

/*
Fetches emojis for a set of notes and comments in parallel and returns a map of note IDs to their emojis.
Gitlab's API does not allow for fetching notes for an entire discussion thread so we have to do it per-note.
*/
func (a *Api) fetchEmojisForNotesAndComments(noteIDs []int) (map[int][]*gitlab.AwardEmoji, error) {
	var wg sync.WaitGroup

	emojis := make(map[int][]*gitlab.AwardEmoji)
	mu := &sync.Mutex{}
	errs := make(chan error, len(noteIDs))
	emojiChan := make(chan struct {
		noteID int
		emojis []*gitlab.AwardEmoji
	}, len(noteIDs))

	for _, noteID := range noteIDs {
		wg.Add(1)
		go func(noteID int) {
			defer wg.Done()
			emojis, _, err := a.client.ListMergeRequestAwardEmojiOnNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, noteID, &gitlab.ListAwardEmojiOptions{})
			if err != nil {
				errs <- err
				return
			}
			emojiChan <- struct {
				noteID int
				emojis []*gitlab.AwardEmoji
			}{noteID, emojis}
		}(noteID)
	}

	/* Close the channels when all goroutines finish */
	go func() {
		wg.Wait()
		close(errs)
		close(emojiChan)
	}()

	/* Collect emojis */
	for e := range emojiChan {
		mu.Lock()
		emojis[e.noteID] = e.emojis
		mu.Unlock()
	}

	/* Check if any errors occurred */
	if len(errs) > 0 {
		for err := range errs {
			if err != nil {
				return nil, err
			}
		}
	}

	return emojis, nil
}

func (a *Api) emojiNoteHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodPost:
		a.postEmojiOnNote(w, r)
	case http.MethodDelete:
		a.deleteEmojiFromNote(w, r)
	default:
		w.Header().Set("Access-Control-Allow-Methods", fmt.Sprintf("%s, %s", http.MethodDelete, http.MethodPost))
		handleError(w, InvalidRequestError{}, "Expected DELETE or POST", http.StatusMethodNotAllowed)
	}
}

/* deleteEmojiFromNote deletes an emoji from a note based on the emoji (awardable) ID and the note's ID */
func (a *Api) deleteEmojiFromNote(w http.ResponseWriter, r *http.Request) {

	suffix := strings.TrimPrefix(r.URL.Path, "/mr/awardable/note/")
	ids := strings.Split(suffix, "/")

	noteId, err := strconv.Atoi(ids[0])
	if err != nil {
		handleError(w, err, "Could not convert note ID to integer", http.StatusBadRequest)
		return
	}

	awardableId, err := strconv.Atoi(ids[1])
	if err != nil {
		handleError(w, err, "Could not convert awardable ID to integer", http.StatusBadRequest)
		return
	}

	res, err := a.client.DeleteMergeRequestAwardEmojiOnNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, noteId, awardableId)

	if err != nil {
		handleError(w, err, "Could not delete awardable", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/pipeline"}, "Could not delete awardable", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{
		Message: "Emoji deleted",
		Status:  http.StatusOK,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}

/* postEmojiOnNote adds an emojis to a note based on the note's ID */
func (a *Api) postEmojiOnNote(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		handleError(w, err, "Could not read request body", http.StatusBadRequest)
		return
	}

	defer r.Body.Close()

	var emojiPost CreateNoteEmojiPost
	err = json.Unmarshal(body, &emojiPost)

	if err != nil {
		handleError(w, err, "Could not unmarshal request body", http.StatusBadRequest)
		return
	}

	awardEmoji, res, err := a.client.CreateMergeRequestAwardEmojiOnNote(a.projectInfo.ProjectId, a.projectInfo.MergeId, emojiPost.NoteId, &gitlab.CreateAwardEmojiOptions{
		Name: emojiPost.Emoji,
	})

	if err != nil {
		handleError(w, err, "Could not post emoji", http.StatusInternalServerError)
		return
	}

	if res.StatusCode >= 300 {
		handleError(w, GenericError{endpoint: "/mr/awardable/note"}, "Could not post emoji", res.StatusCode)
		return
	}

	w.WriteHeader(http.StatusOK)
	response := CreateEmojiResponse{
		SuccessResponse: SuccessResponse{
			Message: "Merge requests retrieved",
			Status:  http.StatusOK,
		},
		Emoji: awardEmoji,
	}

	err = json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	}
}
