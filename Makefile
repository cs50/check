default: run

build:
	docker build -t cs50/check .

rebuild:
	docker build --no-cache -t cs50/check .

run:
	docker run --interactive --publish-all --rm --tty --volume "$(PWD)":/root cs50/check

# Same checks CI runs before pushing (tests/smoke.sh)
test:
	bash tests/smoke.sh cs50/check
