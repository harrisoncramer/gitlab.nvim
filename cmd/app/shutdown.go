package app

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

/*
How long to wait for in-flight requests to finish before shutting down anyway.
Without a deadline a slow Gitlab call keeps the process alive after Neovim quits.
*/
const shutdownTimeout = 10 * time.Second

type killer struct{}

func (k killer) Signal() {}
func (k killer) String() string {
	return "0"
}

type ShutdownHandler interface {
	WatchForShutdown(server *http.Server)
	ServeHTTP(w http.ResponseWriter, r *http.Request)
}

type shutdownService struct {
	sigCh chan os.Signal
	/* How long to wait for in-flight requests. Zero means shutdownTimeout; tests
	shrink it so they do not have to wait out the real deadline. */
	timeout time.Duration
}

func (s shutdownService) WatchForShutdown(server *http.Server) {
	/* Handles shutdown requests */
	<-s.sigCh

	timeout := s.timeout
	if timeout == 0 {
		timeout = shutdownTimeout
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	/* Not fatal: exiting 0 keeps the Lua side from reporting the shutdown as a
	   crash. */
	if err := server.Shutdown(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Server could not shut down gracefully: %s\n", err)
	}
}

/*
WatchForParentExit exits the process once stdin reaches EOF, which happens when
Neovim closes its end of the pipe, i.e. when it dies. This is the only cleanup
that survives a SIGKILL or a crash, where neither /shutdown nor the VimLeavePre
autocmd gets to run. The kernel closes the pipe no matter how the parent died.

The callback exits immediately rather than waiting for running requests to finish,
as /shutdown does. Neovim is already gone, so nobody would see those responses;
waiting could keep the process alive for up to shutdownTimeout for no reason.
*/
func WatchForParentExit() {
	if !isPipeLike(os.Stdin) {
		return
	}

	watchForEOF(os.Stdin, func() { os.Exit(0) })
}

/*
isPipeLike reports whether EOF on the file would really mean that Neovim is gone.
Sockets count too: libuv connects the child's stdin with a socketpair, not a FIFO.
When the server is started by hand, stdin is a terminal or /dev/null, where EOF
means a Ctrl-D or nothing at all.
*/
func isPipeLike(f *os.File) bool {
	info, err := f.Stat()
	if err != nil {
		return false
	}

	return info.Mode()&(os.ModeNamedPipe|os.ModeSocket) != 0
}

/* watchForEOF calls onEOF, in a goroutine, once r is exhausted or errors. */
func watchForEOF(r io.Reader, onEOF func()) {
	go func() {
		_, _ = io.Copy(io.Discard, r)
		onEOF()
	}()
}

type ShutdownRequest struct {
	Restart bool `json:"restart"`
}

/* Shuts down the HTTP server and exit the process by signaling to the shutdown channel */
func (s shutdownService) ServeHTTP(w http.ResponseWriter, r *http.Request) {

	payload := r.Context().Value(payload("payload")).(*ShutdownRequest)

	var text = "Shut down server"
	if payload.Restart {
		text = "Restarted server"
	}

	w.WriteHeader(http.StatusOK)
	response := SuccessResponse{Message: text}

	err := json.NewEncoder(w).Encode(response)
	if err != nil {
		handleError(w, err, "Could not encode response", http.StatusInternalServerError)
	} else {
		s.sigCh <- killer{}
	}
}
