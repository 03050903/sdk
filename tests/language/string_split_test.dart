// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// Issue 24043.

import "package:expect/expect.dart";

class EvilMatch implements Match {
  int get start => 100000000;
  int get end => 3;
}

class EvilIterator implements Iterator {
  bool moveNext() => true;
  EvilMatch get current => new EvilMatch();
}

class EvilIterable extends Iterable {
  Iterator get iterator => new EvilIterator();
}

class EvilPattern {
  Iterable allMatches(String s) => new EvilIterable();
}

void main() {
  Expect.throws(() => "foo".split(new EvilPattern())[0].length,
      (e) => e is RangeError);
}
