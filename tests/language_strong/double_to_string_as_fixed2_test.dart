// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// Test basic integer operations.

import "package:expect/expect.dart";

main() {
  var v = 0.0;
  Expect.throws(() => v.toStringAsFixed(-1), (e) => e is RangeError);
  Expect.throws(() => v.toStringAsFixed(21), (e) => e is RangeError);
  Expect.throws(() => v.toStringAsFixed(null), (e) => e is ArgumentError);
  Expect.throws(() => v.toStringAsFixed(1.5),
      (e) => e is ArgumentError || e is TypeError);
  Expect.throws(() => v.toStringAsFixed("string"),
      (e) => e is ArgumentError || e is TypeError);
  Expect.throws(() => v.toStringAsFixed("3"),
      (e) => e is ArgumentError || e is TypeError);
}
