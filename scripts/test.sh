#!/bin/bash
#
# Run toybox tests.
# TODO:
# - Document the test interface!  Can't exit 1.

usage()
{
  cat <<EOF
Usage:
  scripts/test.sh all
  scripts/test.sh single COMMAND...

Examples:
  $ scripts/test.sh all               # run tests for all commands
  $ scripts/test.sh single grep sed   # run tests for these two commands

  # Test 'grep' on the system, not toybox
  $ TEST_HOST=1 scripts/test.sh commands grep 
EOF
}

[ -z "$TOPDIR" ] && TOPDIR="$(pwd)"

trap 'kill $(jobs -p) 2>/dev/null; exit 1' INT

cd_test_dir()
{
  local cmd=$1
  local test_dir=$TOPDIR/generated/testdir/test_$cmd
  rm -rf $test_dir
  mkdir -p $test_dir
  cd $test_dir
}

setup_test_env()
{
  PATH="$TOPDIR/generated/testdir:$PATH"
  export LC_COLLATE=C

  # Library functions used by .test scripts, e.g. 'testing'.
  . "$TOPDIR"/scripts/runtest.sh

  if [ -f "$TOPDIR/generated/config.h" ]
  then
    export OPTIONFLAGS=:$(echo $(sed -nr 's/^#define CFG_(.*) 1/\1/p' "$TOPDIR/generated/config.h") | sed 's/ /:/g')
  fi
}

# Run tests for specific commands.
single()
{
  # Build individual binaries, e.g. generated/testdir/expr
  [ -z "$TEST_HOST" ] &&
    PREFIX=generated/testdir/ scripts/single.sh "$@" || exit 1

  setup_test_env

  # NOTE: tests dir is not cleared
  # Run tests for the given commands
  for cmd in "$@"
  do
    CMDNAME=$cmd  # .test file uses this
    cd_test_dir $cmd
    . "$TOPDIR"/tests/$cmd.test
  done

  [ $FAILCOUNT -eq 0 ]  # exit success if there 0 failures
}

# Run tests for all commands.
all()
{
  # Build a toybox binary and create symlinks to it.
  [ -z "$TEST_HOST" ] &&
    make install_flat PREFIX=generated/testdir || exit 1

  setup_test_env

  # Run all tests
  for test_file in "$TOPDIR"/tests/*.test
  do
    CMDNAME="${test_file##*/}"
    CMDNAME="${CMDNAME%.test}"

    if [ -h $TOPDIR/generated/testdir/$CMDNAME ] || [ -n "$TEST_HOST" ]
    then
      cd_test_dir $CMDNAME
      . $test_file
    else
      echo "$CMDNAME disabled"
    fi
  done

  [ $FAILCOUNT -eq 0 ]  # exit success if there 0 failures
}

# Adapted from scripts/genconfig

# Find names of commands that can be built standalone in these C files
toys()
{
  grep 'TOY(.*)' "$@" \
    | grep -v TOYFLAG_NOFORK \
    | grep -v "0))" 
    #| sed -rn 's/([^:]*):.*(OLD|NEW)TOY\( *([a-zA-Z][^,]*) *,.*/\1:\3/p'
}

# TODO: Is there a better way to extract these?
toys_with_source()
{
  grep -l 'TOY(.*)' toys/*/*.c | sed -e 's;.*/\([0-9a-z_]\+\)\.c$;\1;' | sort
  #grep -o '/(.*)\.c$'
}

toys_with_tests()
{
  ls tests/*.test | sed -e 's;.*/\([0-9a-z_]\+\)\.test$;\1;'
}

audit()
{
  toys_with_tests > generated/with-tests.txt
  toys_with_source > generated/with-source.txt

  diff -u generated/with-source.txt generated/with-tests.txt 

  wc -l generated/with-*.txt
}

# TODO: Use a different location for the binaries?
rm -rf generated/testdir
mkdir -p generated/testdir

case $1 in
  single|all)
    "$@"
    ;;
  *)
    usage
    ;;
esac
