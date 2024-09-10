package app

import (
	"log"
	"net/http"
	"net/http/httputil"
	"os"
)

func logRequest(r *http.Request) {
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
	_, err = file.Write([]byte("\n-- REQUEST --\n")) //nolint:all
	_, err = file.Write(res)                         //nolint:all
	_, err = file.Write([]byte("\n"))                //nolint:all
}

func logResponse(r *http.Response) {
	file := openLogFile()
	defer file.Close()

	res, err := httputil.DumpResponse(r, true)
	if err != nil {
		log.Fatalf("Error dumping response: %v", err)
		os.Exit(1)
	}

	_, err = file.Write([]byte("\n-- RESPONSE --\n")) //nolint:all
	_, err = file.Write(res)                          //nolint:all
	_, err = file.Write([]byte("\n"))                 //nolint:all
}
