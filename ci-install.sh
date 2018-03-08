#!/bin/bash
#Installs Stack and Z3 if they aren't already.
if [ -z "$(which z3)" ]; then
      apt-get update
      apt-get install curl unzip -y
      curl -sSL https://get.haskellstack.org/ | sh
      curl -L https://github.com/Z3Prover/z3/releases/download/z3-4.6.0/z3-4.6.0-x64-ubuntu-16.04.zip -o z3.zip
      unzip z3.zip
      mv z3-4.6.0-x64-ubuntu-16.04 z3
      mv z3/bin/z3 /usr/bin
      mv z3/include/* /usr/include
      mv z3/bin/libz3.so /usr/lib
      rm    z3.zip
      rm -r z3;
fi