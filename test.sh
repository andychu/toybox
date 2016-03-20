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
 -asan   Run under AddressSanitizer
 -msan   Run under MemorySanitizer
 -ubsan  Run under UndefinedBehaviorSanitizer
 -allsan Run sequentially under the 3 sanitizers

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
USING_SAN=  # Are we running under any Sanitizer?

process_flag() {
  local flag=$1

  # Common between all three
  case $flag in
    -asan|-msan|-ubsan)
      echo 'hi'
      export NOSTRIP=1  # Instruct scripts/make.sh not to strip
      export CC=$SAN_CC
      USING_SAN=1
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
  if [ $# -eq 0 ]
  then
    echo "At least one command is required."
    exit 1
  fi
  case $1 in 
    -)
      process_flag $1
      shift
      ;;
  esac

  for cmd in "$@"
  do
    # Special case for running tests of single binaries: build a standalone
    # binary for each command.   There's no point in building standalone 
    #[ -z "$USING_SAN" ] && BUILD_TARGET=generated/single/$cmd
    [ -z "$USING_SAN" ] && BUILD_TARGET=$cmd

    make $BUILD_TARGET
    # This builds generated

    # Now make a build tree.
    # scripts/test.sh shouldn't do it.

    # TODO: Maybe install.sh here -- get it out of test.sh
    SINGLE_BIN=generated/single/$cmd time scripts/test.sh single $cmd
  done
}

# Flow
# CODE scripts/install.sh -> 
# DATA generated/instlist ->
# CODE which is built with $HOST_CC
# DATA scripts/install.c, which includes
# DATA generated/newtoys.h
# which is built by scripts/make.sh -- this uses sed on toys/*/*.c.  Kind of
# like genconfig.sh
#   stupid isnewer checks should go away.


"$@"
