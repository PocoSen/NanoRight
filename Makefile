.PHONY: test build install clean

test:
	swift test --arch arm64 --disable-xctest --enable-swift-testing

build:
	./scripts/build_app.sh

install: build
	./scripts/install.sh

clean:
	rm -rf .build build
