// Copyright (c) 2
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'static_warning_code_driver_test.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(StaticWarningCodeTest_Kernel);
  });
}

@reflectiveTest
class StaticWarningCodeTest_Kernel extends StaticWarningCodeTest_Driver {
  @override
  bool get enableKernelDriver => true;

  @override
  @failingTest
  test_ambiguousImport_inPart() async {
    return super.test_ambiguousImport_inPart();
  }

  @override
  @failingTest
  test_argumentTypeNotAssignable_annotation_namedConstructor() async {
    return super.test_argumentTypeNotAssignable_annotation_namedConstructor();
  }

  @override
  @failingTest
  test_caseBlockNotTerminated() async {
    return super.test_caseBlockNotTerminated();
  }

  @override
  @failingTest
  test_constWithAbstractClass() async {
    return super.test_constWithAbstractClass();
  }

  @override
  @failingTest
  test_fieldInitializedInInitializerAndDeclaration_final() async {
    return super.test_fieldInitializedInInitializerAndDeclaration_final();
  }

  @override
  @failingTest
  test_finalInitializedInDeclarationAndConstructor_initializers() async {
    return super
        .test_finalInitializedInDeclarationAndConstructor_initializers();
  }

  @override
  @failingTest
  test_finalInitializedInDeclarationAndConstructor_initializingFormal() async {
    return super
        .test_finalInitializedInDeclarationAndConstructor_initializingFormal();
  }

  @override
  @failingTest
  test_finalNotInitialized_inConstructor_1() async {
    return super.test_finalNotInitialized_inConstructor_1();
  }

  @override
  @failingTest
  test_finalNotInitialized_inConstructor_2() async {
    return super.test_finalNotInitialized_inConstructor_2();
  }

  @override
  @failingTest
  test_finalNotInitialized_inConstructor_3() async {
    return super.test_finalNotInitialized_inConstructor_3();
  }

  @override
  @failingTest
  test_importOfNonLibrary() async {
    return super.test_importOfNonLibrary();
  }

  @override
  @failingTest
  test_invalidOverride_defaultOverridesNonDefault() async {
    return super.test_invalidOverride_defaultOverridesNonDefault();
  }

  @override
  @failingTest
  test_invalidOverride_defaultOverridesNonDefault_named() async {
    return super.test_invalidOverride_defaultOverridesNonDefault_named();
  }

  @override
  @failingTest
  test_invalidOverride_defaultOverridesNonDefaultNull() async {
    return super.test_invalidOverride_defaultOverridesNonDefaultNull();
  }

  @override
  @failingTest
  test_invalidOverride_defaultOverridesNonDefaultNull_named() async {
    return super.test_invalidOverride_defaultOverridesNonDefaultNull_named();
  }

  @override
  @failingTest
  test_invalidOverride_nonDefaultOverridesDefault() async {
    return super.test_invalidOverride_nonDefaultOverridesDefault();
  }

  @override
  @failingTest
  test_invalidOverride_nonDefaultOverridesDefault_named() async {
    return super.test_invalidOverride_nonDefaultOverridesDefault_named();
  }

  @override
  @failingTest
  test_invalidOverrideDifferentDefaultValues_named() async {
    return super.test_invalidOverrideDifferentDefaultValues_named();
  }

  @override
  @failingTest
  test_invalidOverrideDifferentDefaultValues_positional() async {
    return super.test_invalidOverrideDifferentDefaultValues_positional();
  }

  @override
  @failingTest
  test_newWithAbstractClass() async {
    return super.test_newWithAbstractClass();
  }

  @override
  @failingTest
  test_newWithUndefinedConstructorDefault() async {
    return super.test_newWithUndefinedConstructorDefault();
  }

  @override
  @failingTest
  test_notEnoughRequiredArguments_getterReturningFunction() async {
    return super.test_notEnoughRequiredArguments_getterReturningFunction();
  }

  @override
  @failingTest
  test_redirectToMissingConstructor_unnamed() async {
    return super.test_redirectToMissingConstructor_unnamed();
  }
}
