#!/bin/bash
#
# Usage:
#   ./sancov.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

src() {
cat > _tmp/cov.cc <<EOF
#include <stdio.h>
__attribute__((noinline))
void foo() { printf("foo\n"); }

int main(int argc, char **argv) {
  if (argc == 2)
    foo();
  printf("main\n");
}
EOF
}

c-src() {
cat > _tmp/cov.c <<EOF
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>  // _exit

__attribute__((noinline))
void foo() { printf("foo\n"); }

int main(int argc, char **argv) {
  if (argc == 2)
    foo();
  printf("main\n");
  _exit(0);  // NO COVERAGE
}
EOF
}


readonly CLANG_DIR=~/install/clang+llvm-3.8.0-x86_64-linux-gnu-ubuntu-14.04

build() {
  #$CLANG_DIR/bin/clang++ -g _tmp/cov.cc -fsanitize=address -fsanitize-coverage=func
  $CLANG_DIR/bin/clang -g _tmp/cov.c -fsanitize=address -fsanitize-coverage=func
}

run() {
  ASAN_OPTIONS=coverage=1 ./a.out
  ls -l *sancov
}

cpp-main() {
  rm -f *.sancov

  src
  build 
  run
}

# PROBLEM: Does toybox do some kind of early exit?  Try a bigger C program?
# Or put a breakpoint where it exits?  Maybe it if doesn't reach the end of
# main?
# In the case of a memory sanitizer error, I thik it might exit immediately.
# So it's a side effect.

# Bug is that toybox always calls _exit() instead of exit(), in xexit
#
# Fix is just to call exit().  Could add an #ifdef I guess.

c-main() {

  rm -f *.sancov

  c-src
  build 
  run
}

"$@"

