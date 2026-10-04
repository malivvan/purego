#!/bin/sh -e

# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Ebitengine Authors

# BSD tests run within QEMU on Ubuntu.
# vmactions/*-vm only supports a single "step" where it
# brings down the VM at the end of the step, so all
# the commands to run need to be put into this single block.

echo "Running tests on $(uname -a) at $PWD"

PATH=$PATH:/usr/local/go/bin/

# verify Go is available
go version

echo "=> go build"
go build -v ./...
# Compile without optimization to check potential stack overflow.
# The option '-gcflags=all=-N -l' is often used at Visual Studio Code.
# See also https://go.googlesource.com/vscode-go/+/HEAD/docs/debugging.md#launch and the issue hajimehoshi/ebiten#2120.
go build "-gcflags=all=-N -l" -v ./...

# Check cross-compiling Windows binaries.
env GOOS=windows GOARCH=386 go build -v ./...
env GOOS=windows GOARCH=amd64 go build -v ./...
env GOOS=windows GOARCH=arm64 go build -v ./...

# Check cross-compiling macOS binaries.
env GOOS=darwin GOARCH=amd64 go build -v ./...
env GOOS=darwin GOARCH=arm64 go build -v ./...

# Check cross-compiling Linux binaries.
env GOOS=linux GOARCH=amd64 go build -v ./...
env GOOS=linux GOARCH=arm64 go build -v ./...

# Check cross-compiling FreeBSD binaries.
#
# Unlike upstream purego these must build with no -gcflags at all. Upstream
# needed -gcflags="github.com/ebitengine/purego/internal/fakecgo=-std" to make
# the compiler accept the //go:cgo_export_dynamic directives in
# internal/fakecgo/freebsd.go; that file dropped those directives so that BSD
# builds require no extra flags. Keep these lines bare: they are the regression
# guard for that rule. Re-adding a -gcflags override here would hide exactly
# the breakage this script is meant to catch.
env GOOS=freebsd GOARCH=amd64 go build -v ./...
env GOOS=freebsd GOARCH=arm64 go build -v ./...

# Check cross-compiling NetBSD binaries.
env GOOS=netbsd GOARCH=amd64 go build -v ./...
env GOOS=netbsd GOARCH=arm64 go build -v ./...

if [ "$(uname)" = "FreeBSD" ]; then
  echo "=> go build (plugin)"
  # Make sure that plugin buildmode works since we save the R15 register (#254).
  # Plugin buildmode is only supported on Linux, FreeBSD and macOS, so this is
  # FreeBSD-only. Upstream used the (now removed) examples/libc here;
  # internal/buildtest is the only main package left in this tree.
  go build -buildmode=plugin ./internal/buildtest
fi

echo "=> go mod vendor"
mkdir /tmp/vendoring
cd /tmp/vendoring
go mod init foo
echo 'package main' > main.go
echo 'import (' >> main.go
echo '  _ "github.com/malivvan/purego"' >> main.go
echo ')' >> main.go
echo 'func main() {}' >> main.go
go mod edit -replace github.com/malivvan/purego=$GITHUB_WORKSPACE
go mod tidy
go mod vendor
go build -v .

cd $GITHUB_WORKSPACE

# CGO_ENABLED=0 is exercised on NetBSD only.
#
# On FreeBSD it cannot run any more: without //go:cgo_export_dynamic in
# internal/fakecgo/freebsd.go, the environ/__progname symbols that libc.so.7
# refers to are no longer put in the dynamic symbol table, so a CGO_ENABLED=0
# FreeBSD binary that links libc.so.7 cannot resolve them at load time. FreeBSD
# is a compile-only target for this copy of purego; the flag-free cross-compiles
# above cover it, and the CGO_ENABLED=1 runs below cover its runtime behavior.
if [ "$(uname)" = "NetBSD" ]; then
  echo "=> go test CGO_ENABLED=0"
  env CGO_ENABLED=0 go test -shuffle=on -v -count=10 ./...

  echo "=> go test CGO_ENABLED=0 w/o optimization"
  env CGO_ENABLED=0 go test "-gcflags=all=-N -l" -v ./...
fi

echo "=> go test CGO_ENABLED=1"
env CGO_ENABLED=1 go test -shuffle=on -v -count=10 ./...

echo "=> go test CGO_ENABLED=1 w/o optimization"
env CGO_ENABLED=1 go test "-gcflags=all=-N -l" -v ./...

echo "=> go test race"
go test -race -shuffle=on -v -count=10 ./...
