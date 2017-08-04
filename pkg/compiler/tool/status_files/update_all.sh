#!/usr/bin/env bash
# Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

# Script to update the dart2js status lines for all tests running with the
# $dart2js_with_kernel test configuration.

repodir=$(cd $(dirname ${BASH_SOURCE[0]})/../../../../; pwd)
dart="out/ReleaseX64/dart"
update_script=$(dirname ${BASH_SOURCE[0]})/update_from_log.dart
sdk="out/ReleaseX64/dart-sdk"

tmp=$(mktemp -d)

function update_suite {
  local suite=$1
  echo "running '$suite' minified tests"
  ./tools/test.py -m release -c dart2js -r d8 --dart2js-batch \
      --use-sdk --minified --dart2js-with-kernel \
      $suite > $tmp/$suite-minified.txt

  echo "processing '$suite' minified tests status changes"
  $dart $update_script minified $tmp/$suite-minified.txt

  echo "running '$suite' host-checked tests"
  ./tools/test.py -m release -c dart2js -r d8 --dart2js-batch --host-checked \
    --dart2js-options="--library-root=$sdk" --dart2js-with-kernel \
    $suite > $tmp/$suite-checked.txt

  echo "processing '$suite' checked tests status changes"
  $dart $update_script checked $tmp/$suite-checked.txt
}


pushd $repodir > /dev/null
./tools/build.py -m release create_sdk
update_suite dart2js_native
update_suite dart2js_extra
update_suite language
update_suite language_2
update_suite corelib
update_suite corelib_2

rm -rf $tmp
popd > /dev/null
