default: help

PROJECTNAME=$(shell basename "$(PWD)")

## compile: build golang project
compile:
	@cd cmd && go build -o bin && mv bin ../bin
## test: run golang project tests
test:
	@cd cmd/app && go test

.PHONY: help
all: help
help: makefile
	@echo
	@echo " Choose a command run in "$(PROJECTNAME)":"
	@echo
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo
