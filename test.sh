#!/bin/bash
#
# Run toybox tests
#
# Usage:
#   ./test.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

usage() {
  cat <<EOF
Runs toybox tests, make sure to build the required binaries.

  ./test.sh all [OPTION]                # Run all tests
  ./test.sh single [OPTION] COMMAND...  # Run tests for the given commands

Flags:
 -asan  Run under AddressSanitizer
 -msan  Run under MemorySanitizer
 -ubsan Run under UndefinedBehaviorSanitizer

See http://clang.llvm.org/docs/index.html for details on these tools.

You should set CLANG_DIR to the location of pre-built binaries for Clang,
vailable at http://llvm.org/releases/download.html.  Otherwise it will use
'clang' in your PATH (which are often old).

Example:
  $ export CLANG_DIR=~/install/clang+llvm-3.8.0-x86_64-linux-gnu-ubuntu-14.04
  $ ./test.sh single -asan grep sed
EOF
}

if [ -n "$CLANG_DIR" ]
then
  # These are needed to show line numbers in stack traces.
  sym=$CLANG_DIR/bin/llvm-symbolizer
	export ASAN_SYMBOLIZER_PATH=$sym
	export MSAN_SYMBOLIZER_PATH=$sym
	export UBSAN_SYMBOLIZER_PATH=$sym
	SAN_CC=$CLANG_DIR/bin/clang
else
	SAN_CC=clang
fi

BUILD_TARGET=toybox

process_flag() {
  local flag=$1

  # Common between all three
  case $flag in
    -asan|-msan|-ubsan)
      echo 'hi'
      export NOSTRIP=1  # Instruct scripts/make.sh not to strip
      export CC=$SAN_CC
      ;;
  esac

  case $flag in
    -asan)
      echo 'asan'
      export CFLAGS='-fsanitize=address -g'
      BUILD_TARGET=toybox_asan
      ;;
    -msan)
      echo 'msan'
      export CFLAGS='-fsanitize=memory -g'
      BUILD_TARGET=toybox_msan
      ;;
    -ubsan)
      echo 'ubsan'
      export CFLAGS='-fsanitize=undefined -fno-omit-frame-pointer -g'
      export UBSAN_OPTIONS='print_stacktrace=1'
      BUILD_TARGET=toybox_ubsan
      ;;
  esac
}

# TODO: Add timing?  That only prints if it succeeds

all() {
  make $BUILD_TARGET
  TOYBOX_BIN=$BUILD_TARGET ./test.sh all
}

single() {
  for cmd in "$@"
  do
    #make single/$cmd
    # NOTE: under asan, etc. we don't build single binaries.  We s
    make $BUILD_TARGET

    # TODO: Maybe install.sh here -- get it out of test.sh
    SINGLE_BIN=generated/single/$cmd time scripts/test.sh single $cmd
  done
}

"$@"
