// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

main() {
  foo(/*bc:1*/ bar(), baz: /*bc:2*/ baz());
}

foo(int bar, {int baz}) {
  print("foo!");
}

int bar() {
  return 42;
}

int baz() {
  return 42;
}
