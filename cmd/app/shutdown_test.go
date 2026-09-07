package app

import (
	"fmt"
	"net"
	"net/http"
	"os"
	"sync"
	"syscall"
	"testing"
	"time"
)

/*
WatchForShutdown must not wait for an in-flight request forever. Before the
shutdown context had a deadline, a single request still waiting on Gitlab kept
the process alive after Neovim had already quit.
*/
func TestWatchForShutdownGivesUpOnInFlightRequests(t *testing.T) {
	/* Blocks until the test is over, standing in for a slow Gitlab call */
	handlerDone := make(chan struct{})
	defer close(handlerDone)

	requestReceived := make(chan struct{})

	server := &http.Server{
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			close(requestReceived)
			<-handlerDone
		}),
	}

	listener, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		_ = server.Serve(listener)
	}()
	defer func() { _ = server.Close() }()

	url := fmt.Sprintf("http://%s/", listener.Addr().String())
	go func() {
		resp, err := http.Get(url)
		if err == nil {
			_ = resp.Body.Close()
		}
	}()

	/* Only shut down once the handler is actually running, otherwise the server
	would be idle and would shut down immediately whether it is bounded or not. */
	select {
	case <-requestReceived:
	case <-time.After(5 * time.Second):
		t.Fatal("Handler never received the request")
	}

	s := shutdownService{sigCh: make(chan os.Signal, 1), timeout: 100 * time.Millisecond}
	s.sigCh <- killer{}

	returned := make(chan time.Duration, 1)
	go func() {
		start := time.Now()
		s.WatchForShutdown(server)
		returned <- time.Since(start)
	}()

	select {
	case elapsed := <-returned:
		/* A lower bound alone would also pass if the function blocked for 100ms for
		some unrelated reason. The upper bound shows that it was the deadline that
		released the wait, not some other delay. */
		if elapsed < s.timeout {
			t.Errorf("Returned after %v, before the %v deadline", elapsed, s.timeout)
		}
		if elapsed > time.Second {
			t.Errorf("Returned after %v, long past the %v deadline: it did not give up on the request", elapsed, s.timeout)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("WatchForShutdown did not return: it is still waiting for the request")
	}
}

/* An idle server should still shut down straight away, well inside the deadline. */
func TestWatchForShutdownReturnsImmediatelyWhenIdle(t *testing.T) {
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})}

	listener, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		_ = server.Serve(listener)
	}()

	s := shutdownService{sigCh: make(chan os.Signal, 1), timeout: 5 * time.Second}
	s.sigCh <- killer{}

	returned := make(chan struct{})
	go func() {
		s.WatchForShutdown(server)
		close(returned)
	}()

	select {
	case <-returned:
	case <-time.After(2 * time.Second):
		t.Fatal("Idle server did not shut down promptly")
	}
}

/*
The default timeout applies when the service does not set one. If the fallback
is dropped, the context expires immediately and Shutdown gives up before the
in-flight request finishes.
*/
func TestWatchForShutdownDefaultsToShutdownTimeout(t *testing.T) {
	handlerDone := make(chan struct{})
	requestReceived := make(chan struct{})

	server := &http.Server{
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			close(requestReceived)
			<-handlerDone
		}),
	}

	listener, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		_ = server.Serve(listener)
	}()
	defer func() { _ = server.Close() }()

	url := fmt.Sprintf("http://%s/", listener.Addr().String())
	go func() {
		resp, err := http.Get(url)
		if err == nil {
			_ = resp.Body.Close()
		}
	}()

	select {
	case <-requestReceived:
	case <-time.After(5 * time.Second):
		t.Fatal("Handler never received the request")
	}

	var once sync.Once
	release := func() { once.Do(func() { close(handlerDone) }) }
	/* Lets the handler finish shortly after the shutdown starts: the fallback
	keeps the context alive long enough for Shutdown to wait it out. */
	time.AfterFunc(200*time.Millisecond, release)
	defer release()

	s := shutdownService{sigCh: make(chan os.Signal, 1)}
	assert(t, s.timeout, time.Duration(0))
	assert(t, shutdownTimeout, 10*time.Second)
	s.sigCh <- killer{}

	start := time.Now()
	s.WatchForShutdown(server)
	elapsed := time.Since(start)

	if elapsed < 100*time.Millisecond {
		t.Errorf("Returned after %v, before the handler finished: the context expired immediately, so the default timeout was not applied", elapsed)
	}
}

/* EOF on the pipe means the process that spawned the server is gone. */
func TestWatchForEOFFiresWhenTheWriteEndCloses(t *testing.T) {
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = reader.Close() }()

	fired := make(chan struct{})
	watchForEOF(reader, func() { close(fired) })

	select {
	case <-fired:
		t.Fatal("Fired while the write end was still open")
	case <-time.After(200 * time.Millisecond):
	}

	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}

	select {
	case <-fired:
	case <-time.After(5 * time.Second):
		t.Fatal("Did not fire after the write end closed")
	}
}

/*
The parent may die between the process starting and the watch beginning: EOF
that is already pending when watchForEOF starts must still fire.
*/
func TestWatchForEOFFiresOnAlreadyClosedPipe(t *testing.T) {
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	/* Simulate that Neovim dies before the EOF watch even starts */
	defer func() { _ = reader.Close() }()
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}

	fired := make(chan struct{})
	watchForEOF(reader, func() { close(fired) })

	select {
	case <-fired:
	case <-time.After(5 * time.Second):
		t.Fatal("Did not fire on an already-exhausted pipe")
	}
}

/* Data on stdin must not be mistaken for the parent going away. */
func TestWatchForEOFIgnoresWrites(t *testing.T) {
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = reader.Close() }()
	defer func() { _ = writer.Close() }()

	fired := make(chan struct{})
	watchForEOF(reader, func() { close(fired) })

	if _, err := writer.WriteString("some noise\n"); err != nil {
		t.Fatal(err)
	}

	select {
	case <-fired:
		t.Fatal("Fired on a write rather than on EOF")
	case <-time.After(200 * time.Millisecond):
	}
}

/*
Only a pipe means "spawned by the plugin". Started by hand, stdin is a terminal
or /dev/null, and EOF there must not shut the server down.
*/
func TestIsPipeLike(t *testing.T) {
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = reader.Close() }()
	defer func() { _ = writer.Close() }()
	assert(t, isPipeLike(reader), true)

	devNull, err := os.Open(os.DevNull)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = devNull.Close() }()
	assert(t, isPipeLike(devNull), false)

	regular, err := os.CreateTemp(t.TempDir(), "stdin")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = regular.Close() }()
	assert(t, isPipeLike(regular), false)
}

/* Neovim connects the child's stdin with a socketpair, not with a FIFO. */
func TestIsPipeLikeAcceptsSocketpair(t *testing.T) {
	fds, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_STREAM, 0)
	if err != nil {
		t.Fatal(err)
	}

	local := os.NewFile(uintptr(fds[0]), "socketpair")
	defer func() { _ = local.Close() }()
	remote := os.NewFile(uintptr(fds[1]), "socketpair")
	defer func() { _ = remote.Close() }()

	assert(t, isPipeLike(local), true)
}
