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

die() { echo "$@"; exit 1; }

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

TOYBOX_BIN=toybox
SAN_FLAG=  # Are we running under any Sanitizer?

process_flag() {
  local flag=$1

  # Common between all three
  case $flag in
    -asan|-msan|-ubsan)
      echo 'hi'
      export NOSTRIP=1  # Instruct scripts/make.sh not to strip
      export CC=$SAN_CC
      SAN_FLAG=$flag
      ;;
    *)
      die "Invalid flag $flag"
      ;;
  esac

  case $flag in
    -asan)
      echo 'asan'
      export CFLAGS='-fsanitize=address -g'
      TOYBOX_BIN=toybox_asan
      ;;
    -msan)
      echo 'msan'
      export CFLAGS='-fsanitize=memory -g'
      TOYBOX_BIN=toybox_msan
      ;;
    -ubsan)
      echo 'ubsan'
      export CFLAGS='-fsanitize=undefined -fno-omit-frame-pointer -g'
      export UBSAN_OPTIONS='print_stacktrace=1'
      TOYBOX_BIN=toybox_ubsan
      ;;
  esac
}

# Adapted from genconfig.sh
toys_grep() {
  grep 'TOY(.*)' toys/*/*.c | grep -v TOYFLAG_NOFORK | grep -v "0))" | \
    sed -rn 's/([^:]*):.*(OLD|NEW)TOY\( *([a-zA-Z][^,]*) *,.*/\3/p' | sort
}

# Make a dir, linking every binary to the toybox binary.
make_tree_dir() {
  local tree_dir=$1
  local toybox_bin=$2

  # Make there aren't old commands lying around.
  rm -rf $tree_dir
  mkdir -p $tree_dir
  toys_grep | xargs -I {} -- ln -s $toybox_bin $tree_dir/{}
}

# TODO: Add timing?  That only prints if it succeeds

all() {
  if [ $# -gt 0 ]
  then
    case $1 in 
      -*)
        process_flag $1
        shift
        ;;
    esac
  fi

  make $TOYBOX_BIN

  local tree_dir=generated/tree-all$SAN_FLAG
  # The symlinks have to go up two levels to the root.
  make_tree_dir $tree_dir ../../$TOYBOX_BIN

  PATH=$tree_dir:$PATH scripts/test.sh all
}

single() {
  [ $# -eq 0 ] && die "At least one command is required."
  case $1 in 
    -*)
      process_flag $1
      shift
      ;;
  esac

  make $TOYBOX_BIN

  for cmd in "$@"
  do
    # TODO: change to generated/single/$cmd
    [ -z "$SAN_FLAG" ] && make $cmd

    # e.g. generated/tree-grep or generated/tree-grep-asan
    local tree_dir=generated/tree-$cmd$SAN_FLAG
    make_tree_dir $tree_dir ../../$TOYBOX_BIN

    PATH=$tree_dir:$PATH scripts/test.sh single $cmd
  done
}


# Adapted from make.sh.  Doesn't work because we get '-toysh' for some reason
toys_sed() {
  sed -n -e 's/^USE_[A-Z0-9_]*(/&/p' toys/*/*.c \
	| sed -e 's/\(.*TOY(\)\([^,]*\),\(.*\)/\2/' | sort
}

use_lines() {
  sed -n -e 's/^USE_[A-Z0-9_]*(/&/p' toys/*/*.c 
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
