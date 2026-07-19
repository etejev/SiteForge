.PHONY: dev build test verify watch next loop status release-local

dev:
	./sf dev

build:
	./sf build

test:
	./sf test

verify:
	./sf verify

watch:
	./sf watch

next:
	./sf next

loop:
	./sf loop $${COUNT:-5}

status:
	./sf status

release-local:
	./sf release-local

