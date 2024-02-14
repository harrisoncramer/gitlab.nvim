package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"sync"
	"unicode/utf8"

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

/*
attachEmojisToApi reads the emojis from our external JSON file
and attaches them to the API so that they can be looked up later
*/
func attachEmojisToApi(a *api) error {

	e, err := os.Executable()
	if err != nil {
		return err
	}

	binPath := fmt.Sprintf(path.Dir(e))
	filePath := fmt.Sprintf("%s/config/emojis.json", binPath)

	reader, err := a.fileReader.ReadFile(filePath)

	if err != nil {
		return errors.New(fmt.Sprintf("Could not find emojis at %s", filePath))
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
FetchEmojisForNotes fetches emojis for a set of notes in parallel and returns a map of note IDs to their emojis.
Gitlab's API does not allow for fetching notes for an entire discussion thread so we have to do it per-note.
*/
func (a *api) fetchEmojisForNotes(noteIDs []int) (map[int][]*gitlab.AwardEmoji, error) {
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

func isSingleCodePointEmoji(emoji string) error {
	if utf8.RuneCountInString(emoji) == 1 {
		return nil
	}
	return errors.New("the emoji is not a single code point")
}

// func getEmojiByName(name string) (string, error) {
//
// 	// Check if it's a non-single point code emoji
// 	err := isSingleCodePointEmoji(name)
// 	if err != nil {
// 		return "", errors.New("Emojis must be single-point in terminal views")
// 	}
//
// 	emoji, ok := a.emojiList[name]
// 	if ok == true {
// 		return emoji, nil
// 	}
//
// 	return "", errors.New("Emoji not found")
// }
