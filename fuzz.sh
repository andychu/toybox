#!/bin/bash
#
# Usage:
#   ./run.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

download() {
  wget --directory ~/src http://lcamtuf.coredump.cx/afl/releases/afl-latest.tgz
}

build() {
  time make
}

# 15K lines of code.  Most of it is in 7K lines of code in afl-fuzz.c.
count() {
  find . -name '*.c' -o -name '*.h' | xargs wc -l
}

readonly AFL_DIR=~/src/afl-2.06b/
readonly TOYBOX_DIR=~/git/other/toybox/

# Problem: not everything builds with afl-gcc?  I'm getting an error in
# rfkill.c and ps.c.
# toys/posix/ps.c:1380:72: error: macro "strchr" passed 5 arguments, but takes just 2
#
# It's because they are macros.  But I'm not sure why afl-gcc flags this and
# not gcc.  I guess you need to make an AFL_VERBOSE?

build-toybox() {
  local clean=${1:-}  # pass "clean"
  pushd $TOYBOX_DIR

  if test -n "$clean"; then
    make clean
  fi

  # -g: generate debug info
  # -O0, -fno-omit: hm even with these flags, I still get <optimized out>
  #local cflags='-g -O0 -fno-omit-frame-pointer'
  local cflags='-g'

  CC=$AFL_DIR/afl-gcc CFLAGS="$cflags" make

  # Ends up as 268 KB instead of 256 KB (stripped).
  # With -g: ends up at 325 KB.
  ls -l toybox toybox_unstripped
  popd
}

# Why am I not getting source anymore?
show-debug() {
  readelf -s $TOYBOX_DIR/toybox_unstripped
}

# Ah OK, it pipes to apport!  Interesting.  I learned a new kernel feature.
#
# http://man7.org/linux/man-pages/man5/core.5.html
#
# - You can name core dumps with % format specifiers, like PID.
# - Or if it starts with '|' and points to an asbolute path, you can get core
# dumps on stdin.

save-core-config() {
  local out=_tmp/core_pattern.txt
  cat /proc/sys/kernel/core_pattern | tee $out
  echo "Saved as $out"
}

# Restore default configuration because afl-fuzz will interact poorly with
# apport.
setup-fuzz() {
  sudo sh -c 'echo core >/proc/sys/kernel/core_pattern'
}

restore-core-config() {
  local input=_tmp/core_pattern.txt
  sudo sh -c "cat >/proc/sys/kernel/core_pattern <$input"
  echo "Restored from $input"
  cat /proc/sys/kernel/core_pattern
}

# TODO: Do I need to write a toybox harness that reads from stdin, or from a
# file?  Do any commands already read from a file?  "sort" does.
#
# biggest tests:
# - chmod
# - ifconfig
# - sed
# - chattr
#
# Oh yeah sed
#
# sed -f takes a script as a file.
#
# Implementation notes:
# - sed regex: is it shared with grep and expr?

# afl-fuzz warns that the kernel may miss very short-lived processes.  TODO: I
# think the test harness for toybox shouldn't cause short-lived processes?  By
# default it is a fork server?  How does that work?  It forks and calls main()?
afl-fuzz() {
  AFL_SKIP_CPUFREQ=1  $AFL_DIR/afl-fuzz "$@"
}

toybox() {
  $TOYBOX_DIR/toybox "$@"
}

toybox-unstripped() {
  $TOYBOX_DIR/toybox_unstripped "$@"
}

write-input() {
  seq 10 > _tmp/input.txt
}

sedc-cases() {
  echo -- 1
  "$@" -e 'c\' <<EOF
a
b
c
EOF

  # space
  echo -- 2
  "$@" -e 'c\ ' <<EOF
a
b
c
EOF

  # semicolon
  echo -- 3
  "$@" -e 'c\;' <<EOF
a
b
c
EOF

  # semicolon
  echo -- 4
  "$@" -e 'c;' <<EOF
a
b
c
EOF

  echo -- 5
  "$@" -e 'c\HI' <<EOF
a
b
c
EOF

  echo -- 6
  "$@" -e 'c\
;' <<EOF
a
b
c
EOF

}

sedc-compare() {
  echo
  sedc-cases sed

  echo
  echo TOYBOX
  echo
  sedc-cases ~/git/other/toybox/toybox_unstripped sed
}

sed-demo() {
  mkdir -p _tmp
  write-input
  echo 's/5/xxx/' > _tmp/prog.txt
  toybox sed -f _tmp/prog.txt _tmp/input.txt
}

write-sed-cases() {
  local dir=$1
  echo 's/5/xxx/' > $dir/1.txt
}

# Performance note: Getting 4000 exec/sec
# Is there a way to get higher?  I guess you could skip main() stuff and go
# straight to the command?  I don't think toybox does its own fork.
#
# _AFL_INIT().  Could put that right before the toy_init() to skip as much as
# possible.  toy_init() does the option parsing.

fuzz-sed() {
  mkdir -p _tmp/sed/{cases,findings}
  write-input

  write-sed-cases _tmp/sed/cases

  pushd _tmp/sed
  afl-fuzz -i cases -o findings -- $TOYBOX_DIR/toybox sed -f @@ ../input.txt
  popd
}

grep-demo() {
  mkdir -p _tmp
  write-input
  echo '^.$' > _tmp/pat.txt
  toybox grep -f _tmp/pat.txt _tmp/input.txt
}

write-grep-cases() {
  local dir=$1
  echo '^.$' > $dir/1.txt
}

fuzz-grep() {
  mkdir -p _tmp/grep/{cases,findings}
  write-input  # simple input file

  write-grep-cases _tmp/grep/cases

  # change directory in case it writes stuff into the dir
  pushd _tmp/grep
  afl-fuzz -i cases -o findings -- $TOYBOX_DIR/toybox grep -f @@ ../input.txt
  popd
}

# NOTE: With 4 cases, adding 777, afl-fuzz complains that they are redundant?
# Do we have to inspect the code to get good cases?

# After about 2 minutes, afl-fuzz shows 60 "total paths".  5000 tests per
# second.
# After 4 minutes, we have 2 "cycles" done.  What does that mean?

# TODO: Use afl-cmin on the testdata!
write-chmod-cases() {
  local dir=$1
  rm --verbose $dir/*
  echo '+w' > $dir/1.txt
  echo 'g-X' > $dir/2.txt
  echo '644' > $dir/3.txt
}

fuzz-chmod() {
  mkdir -p _tmp/chmod/{cases,findings}

  write-chmod-cases _tmp/chmod/cases

  local test_file=$TMPFS_DIR/file  # put it on tmpfs so we don't mess with metadata
  #echo TEST > $test_file

  # afl-fuzz replaces @@ anywhere in the arg.
  # TODO: build toybox with CFG_ARG_FILE_TESTING.
  pushd _tmp/chmod
  afl-fuzz -i cases -o findings -- $TOYBOX_DIR/toybox chmod 'ARG-FILE:@@' $test_file
  popd
}

# TODO:
# - How to fuzz printf with multiple args?
# - You have to get afl-fuzz to generate multiple combos?  Tokenize them
# somehow?
# - Or do an afl-minc on a corpus?

show-tests() {
  local cmd=${1:-chmod}
  cat $TOYBOX_DIR/tests/$cmd.test
}

test-len() {
  wc -l $TOYBOX_DIR/tests/*.test | sort -n
}

# in GNU sed, 'c\' gives no lines.  In the fixed toybox, it gives 10 lines.

# commit 3a4917a5bb131fbe358c1c33ca71296774881fe1
# Author: Rob Landley <rob@landley.net>
# Date:   Tue Jan 13 03:35:37 2015 -0600

# sed s/// can have line continuations in the replacement part, with or without a \ escaping the newline.

repro-sed() {
  build-toybox
  toybox-unstripped sed -e 'c\' _tmp/input.txt
  echo DONE
}

# Hm this hang doesn't repro?
repro-sed2() {
  local prog='_tmp/sed/findings/hangs/id:000000,src:000014,op:havoc,rep:8'

  echo PROG
  od -c $prog
  echo

  #toybox-unstripped sed -f "$prog" _tmp/input.txt
  toybox sed -f "$prog" _tmp/input.txt
}

debug-sed() {
  local case=~/git/scratch/afl-fuzz/_tmp/findings/crashes/id:000000,sig:11,src:000000,op:havoc,rep:64

  build-toybox
  #gdb -tui --args ~/git/other/toybox/toybox_unstripped sed -e 'c\' _tmp/input.txt

  pushd $TOYBOX_DIR
  gdb --tui --args ./toybox_unstripped sed -e 'c\' _tmp/input.txt
  popd
}

# TODO:
# - Build debug build.  And get stack trace with line numbers?  How to do that?
# - Where is the core dump?

# - It fucking writes all this garbage to disk!  How does that happen?  Is it
# instrumenting -o or something?


# Test cases: get them from toybox itself
#
# See toybox/tests/find.test

# TODO: Write your own C program and see how it fuzzes it?  Maybe there is a
# demo online somewhere.


# Copied from srcbook.

readonly TMPFS_DIR=~/afl-fuzz/tmpfs

_make-tmpfs() {
  local mount_dir=$TMPFS_DIR
  mkdir -p $mount_dir
  # 10m should be enough for fuzzing.
  mount -t tmpfs -o size=10m tmpfs $mount_dir
  ls -al $mount_dir
  df -h
}

make-tmpfs() {
  sudo $0 _make-tmpfs
}

# I want to fuzz the chmod +w input.  And arbitrary commands that don't take
# files.

"$@"
