package app

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"os"
)

// LoggingServer is a wrapper around an http.Handler to log incoming requests and outgoing responses.
type LoggingServer struct {
	handler http.Handler
}

type LoggingResponseWriter struct {
	statusCode int
	body       *bytes.Buffer
	http.ResponseWriter
}

func (l *LoggingResponseWriter) WriteHeader(statusCode int) {
	l.statusCode = statusCode
}

func (l *LoggingResponseWriter) Write(b []byte) (int, error) {
	l.body.Write(b)
	return l.ResponseWriter.Write(b)
}

// Logs the request, calls the original handler on the ServeMux, then logs the response
func (l LoggingServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if pluginOptions.Debug.Request {
		logRequest("REQUEST TO GO SERVER", r)
	}
	lrw := &LoggingResponseWriter{ResponseWriter: w, body: &bytes.Buffer{}}
	l.handler.ServeHTTP(lrw, r)
	resp := &http.Response{
		Status:        http.StatusText(lrw.statusCode),
		StatusCode:    lrw.statusCode,
		Body:          io.NopCloser(bytes.NewBuffer(lrw.body.Bytes())), // Use the captured body
		ContentLength: int64(lrw.body.Len()),
		Header:        lrw.Header(),
		Request:       r,
	}
	if pluginOptions.Debug.Response {
		logResponse("RESPONSE FROM GO SERVER", resp) //nolint:errcheck
	}
}

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
	fmt.Fprintf(file, "\n-- %s --\n%s\n", prefix, res) //nolint:errcheck
}

func logResponse(prefix string, r *http.Response) {
	file := openLogFile()
	defer file.Close()

	res, err := httputil.DumpResponse(r, true)
	if err != nil {
		log.Fatalf("Error dumping response: %v", err)
		os.Exit(1)
	}

	fmt.Fprintf(file, "\n-- %s --\n%s\n", prefix, res) //nolint:errcheck
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
