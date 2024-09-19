default: help

PROJECTNAME=$(shell basename "$(PWD)")

## compile: build golang project
compile:
	@go build -o bin ./cmd
## test: run golang project tests
test:
	@go test -v ./...

.PHONY: help
all: help
help: makefile
	@echo
	@echo " Choose a command run in "$(PROJECTNAME)":"
	@echo
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo
