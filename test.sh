#!/bin/bash
#
# Runs toybox tests, making sure to build the required binaries.

set -o nounset
set -o pipefail
set -o errexit

usage() {
  cat <<EOF
Runs toybox tests, making sure to build the required binaries.

  ./test.sh all [OPTION]                # Run all tests
  ./test.sh single [OPTION] COMMAND...  # Run tests for the given commands

Options:
 -asan   Run under AddressSanitizer
 -msan   Run under MemorySanitizer
 -ubsan  Run under UndefinedBehaviorSanitizer

See http://clang.llvm.org/docs/index.html for details on these tools.

Environment variables:
  TEST_HOST:
    Test the command on the host instead of toybox.  Respected by
    scripts/test.sh.
  VERBOSE=1, VERBOSE=fail, DEBUG:
    Show more test output.  Respected by scripts/runtest.sh.
  CLANG_DIR:
    Directory of Clang pre-built binaries, available at
    http://llvm.org/releases/download.html.  You should set CLANG_DIR when
    running with the sanitizers; otherwise it will use 'clang' in your PATH
    (which is often old).

Example:
  $ export CLANG_DIR=~/install/clang+llvm-3.8.0-x86_64-linux-gnu-ubuntu-14.04
  $ ./test.sh single -asan grep sed

EOF
  exit
}

readonly TOPDIR=${TOPDIR:-$PWD}

if [ -n "$CLANG_DIR" ]
then
  # These are needed to show line numbers in stack traces.
  sym=$CLANG_DIR/bin/llvm-symbolizer
	export ASAN_SYMBOLIZER_PATH=$sym
	export MSAN_SYMBOLIZER_PATH=$sym
	export UBSAN_SYMBOLIZER_PATH=$sym
fi

TOYBOX_BIN=toybox
SAN_FLAG=  # Are we running under any Sanitizer?

die() { echo "$@"; exit 1; }

process_flag() {
  local flag=$1

  # Common between all three
  case $flag in
    -asan|-msan|-ubsan)
      SAN_FLAG=$flag
      ;;
    *)
      die "Invalid flag $flag"
      ;;
  esac

  case $flag in
    -asan)
      TOYBOX_BIN=toybox_asan
      ;;
    -msan)
      TOYBOX_BIN=toybox_msan
      ;;
    -ubsan)
      TOYBOX_BIN=toybox_ubsan
      export UBSAN_OPTIONS='print_stacktrace=1'
      ;;
  esac
}

# Print the toys that should be installed.
#
# NOTE: This logic is copied from scripts/genconfig.sh.  That should probably
# write a simple text file of commands.
toys_to_link() {
  grep 'TOY(.*)' toys/*/*.c | grep -v TOYFLAG_NOFORK | grep -v "0))" | \
    sed -rn 's/([^:]*):.*(OLD|NEW)TOY\( *([a-zA-Z][^,]*) *,.*/\3/p' | sort
}

# Make a dir, linking every binary to the toybox binary.
make_toybox_tree() {
  local tree_dir=$1
  local toybox_bin=$2

  # Make there aren't old commands lying around.
  rm -rf $tree_dir
  mkdir -p $tree_dir
  toys_to_link | xargs -I {} -- ln -s $toybox_bin $tree_dir/{}
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
  make_toybox_tree $tree_dir ../../$TOYBOX_BIN

  TOYBOX_TREE_DIR=$TOPDIR/$tree_dir scripts/test.sh all
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
    local tree_dir
    if [ -z "$SAN_FLAG" ]
    then
      tree_dir=generated/tree-$cmd
    else
      # no single binaries
      tree_dir=generated/tree-all$SAN_FLAG
    fi

    make_toybox_tree $tree_dir ../../$TOYBOX_BIN

    # Make the 'single' binary, and copy it over the symlink to toybox in the
    # tree.
    if [ -z "$SAN_FLAG" ]
    then
      make generated/single/$cmd
      cp --verbose --force generated/single/$cmd $tree_dir
    fi

    TOYBOX_TREE_DIR=$TOPDIR/$tree_dir scripts/test.sh single $cmd
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

[ $# -eq 0 ] && usage

case $1 in
  single|all)
    "$@"
    ;;
  *)
    usage
    ;;
esac
