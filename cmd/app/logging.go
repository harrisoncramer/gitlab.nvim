package app

import (
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"os"
)

func logRequest(prefix string, r *http.Request) {
	file := openLogFile()
	defer file.Close()
	token := r.Header.Get("Private-Token")
	r.Header.Set("Private-Token", "REDACTED")
	res, err := httputil.DumpRequest(r, true)
	if err != nil {
		log.Fatalf("Error dumping request: %v", err)
		os.Exit(1)
	}
	r.Header.Set("Private-Token", token)
	_, err = file.Write([]byte(fmt.Sprintf("\n-- %s --\n", prefix))) //nolint:all
	_, err = file.Write(res)                                         //nolint:all
	_, err = file.Write([]byte("\n"))                                //nolint:all
}

func logResponse(prefix string, r *http.Response) {
	file := openLogFile()
	defer file.Close()

	res, err := httputil.DumpResponse(r, true)
	if err != nil {
		log.Fatalf("Error dumping response: %v", err)
		os.Exit(1)
	}

	_, err = file.Write([]byte(fmt.Sprintf("\n-- %s --\n", prefix))) //nolint:all
	_, err = file.Write(res)                                         //nolint:all
	_, err = file.Write([]byte("\n"))                                //nolint:all
}

func openLogFile() *os.File {
	file, err := os.OpenFile(pluginOptions.LogPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("Log file %s does not exist", pluginOptions.LogPath)
		} else if os.IsPermission(err) {
			log.Printf("Permission denied for log file %s", pluginOptions.LogPath)
		} else {
			log.Printf("Error opening log file %s: %v", pluginOptions.LogPath, err)
		}

		os.Exit(1)
	}

	return file
}
