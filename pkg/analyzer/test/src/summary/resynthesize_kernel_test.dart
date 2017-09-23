// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer.test.src.summary.resynthesize_kernel_test;

import 'dart:async';

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/kernel/resynthesize.dart';
import 'package:front_end/byte_store.dart';
import 'package:front_end/compiler_options.dart';
import 'package:front_end/file_system.dart';
import 'package:front_end/src/base/libraries_specification.dart';
import 'package:front_end/src/base/performace_logger.dart';
import 'package:front_end/src/base/processed_options.dart';
import 'package:front_end/src/fasta/uri_translator_impl.dart';
import 'package:front_end/src/incremental/kernel_driver.dart';
import 'package:kernel/kernel.dart' as kernel;
import 'package:kernel/target/targets.dart';
import 'package:kernel/text/ast_to_text.dart' as kernel;
import 'package:kernel/type_environment.dart' as kernel;
import 'package:package_config/packages.dart';
import 'package:path/path.dart' as pathos;
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../context/mock_sdk.dart';
import 'resynthesize_common.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ResynthesizeKernelStrongTest);
  });
}

/// Tests marked with this annotation fail because they test features that
/// were implemented in Analyzer, but are intentionally not included into
/// the Dart 2.0 plan, so will not be implemented by Fasta.
const notForDart2 = const Object();

/// Tests marked with this annotations fail because we either have not triaged
/// them, or know that this is an analyzer problem.
const potentialAnalyzerProblem = const Object();

/// Tests marked with this annotation fail because of a Fasta problem.
class FastaProblem {
  const FastaProblem(String issueUri);
}

@reflectiveTest
class ResynthesizeKernelStrongTest extends ResynthesizeTest {
  static const DEBUG = false;

  final resourceProvider = new MemoryResourceProvider(context: pathos.posix);

  @override
  bool get isSharedFrontEnd => true;

  @override
  bool get isStrongMode => true;

  @override
  Source addLibrarySource(String path, String content) {
    path = resourceProvider.convertPath(path);
    File file = resourceProvider.newFile(path, content);
    return file.createSource();
  }

  @override
  Source addSource(String path, String content) {
    path = resourceProvider.convertPath(path);
    File file = resourceProvider.newFile(path, content);
    return file.createSource();
  }

  @override
  Future<LibraryElementImpl> checkLibrary(String text,
      {bool allowErrors: false, bool dumpSummaries: false}) async {
    new MockSdk(resourceProvider: resourceProvider);

    File testFile = resourceProvider.newFile('/test.dart', text);
    Uri testUri = testFile.toUri();
    String testUriStr = testUri.toString();

    Map<String, LibraryInfo> dartLibraries = {};
    MockSdk.FULL_URI_MAP.forEach((dartUri, path) {
      var name = Uri.parse(dartUri).path;
      dartLibraries[name] =
          new LibraryInfo(name, Uri.parse('file://$path'), const []);
    });

    var uriTranslator = new UriTranslatorImpl(
        new TargetLibrariesSpecification('none', dartLibraries),
        Packages.noPackages);
    var options = new ProcessedOptions(new CompilerOptions()
      ..target = new NoneTarget(new TargetFlags(strongMode: isStrongMode))
      ..reportMessages = false
      ..logger = new PerformanceLog(null)
      ..fileSystem = new _FileSystemAdaptor(resourceProvider)
      ..byteStore = new MemoryByteStore());
    var driver = new KernelDriver(options, uriTranslator);

    KernelResult kernelResult = await driver.getKernel(testUri);

    var libraryMap = <String, kernel.Library>{};
    for (var cycleResult in kernelResult.results) {
      for (var library in cycleResult.kernelLibraries) {
        String uriStr = library.importUri.toString();
        libraryMap[uriStr] = library;
      }
    }

    if (DEBUG) {
      var library = libraryMap[testUriStr];
      print(_getLibraryText(library));
    }

    var resynthesizer =
        new KernelResynthesizer(context, kernelResult.types, libraryMap);
    return resynthesizer.getLibrary(testUriStr);
  }

  @override
  AnalysisOptionsImpl createOptions() =>
      super.createOptions()..strongMode = true;

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30857')
  test_class_constructor_field_formal_multiple_matching_fields() async {
    await super.test_class_constructor_field_formal_multiple_matching_fields();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_class_type_parameters_bound() async {
    // Fasta does not provide a flag for explicit vs. implicit Object bound.
    await super.test_class_type_parameters_bound();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30266')
  test_const_invalid_intLiteral() async {
    await super.test_const_invalid_intLiteral();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30258')
  test_constructor_redirected_factory_named_generic() async {
    await super.test_constructor_redirected_factory_named_generic();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30258')
  test_constructor_redirected_factory_named_imported_generic() async {
    await super.test_constructor_redirected_factory_named_imported_generic();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30258')
  test_constructor_redirected_factory_named_prefixed_generic() async {
    await super.test_constructor_redirected_factory_named_prefixed_generic();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30258')
  test_constructor_redirected_factory_unnamed_generic() async {
    await super.test_constructor_redirected_factory_unnamed_generic();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30258')
  test_constructor_redirected_factory_unnamed_imported_generic() async {
    await super.test_constructor_redirected_factory_unnamed_imported_generic();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30258')
  test_constructor_redirected_factory_unnamed_prefixed_generic() async {
    await super.test_constructor_redirected_factory_unnamed_prefixed_generic();
  }

  @failingTest
  @notForDart2
  test_defaultValue_refersToGenericClass_constructor() async {
    // Analyzer allows the inferred type of a const to refer to type parameters
    // that are in scope; Dart 2.0 infers a different type so that the constant
    // doesn't depend on a (non-constant) type parameter.
    await super.test_defaultValue_refersToGenericClass_constructor();
  }

  @failingTest
  @notForDart2
  test_defaultValue_refersToGenericClass_constructor2() async {
    // Analyzer allows the inferred type of a const to refer to type parameters
    // that are in scope; Dart 2.0 infers a different type so that the constant
    // doesn't depend on a (non-constant) type parameter.
    await super.test_defaultValue_refersToGenericClass_constructor2();
  }

  @failingTest
  @notForDart2
  test_defaultValue_refersToGenericClass_functionG() async {
    // Analyzer allows the inferred type of a const to refer to type parameters
    // that are in scope; Dart 2.0 infers a different type so that the constant
    // doesn't depend on a (non-constant) type parameter.
    await super.test_defaultValue_refersToGenericClass_functionG();
  }

  @failingTest
  @notForDart2
  test_defaultValue_refersToGenericClass_methodG() async {
    // Analyzer allows the inferred type of a const to refer to type parameters
    // that are in scope; Dart 2.0 infers a different type so that the constant
    // doesn't depend on a (non-constant) type parameter.
    await super.test_defaultValue_refersToGenericClass_methodG();
  }

  @failingTest
  @notForDart2
  test_defaultValue_refersToGenericClass_methodG_classG() async {
    // Analyzer allows the inferred type of a const to refer to type parameters
    // that are in scope; Dart 2.0 infers a different type so that the constant
    // doesn't depend on a (non-constant) type parameter.
    await super.test_defaultValue_refersToGenericClass_methodG_classG();
  }

  @failingTest
  @notForDart2
  test_defaultValue_refersToGenericClass_methodNG() async {
    // Analyzer allows the inferred type of a const to refer to type parameters
    // that are in scope; Dart 2.0 infers a different type so that the constant
    // doesn't depend on a (non-constant) type parameter.
    await super.test_defaultValue_refersToGenericClass_methodNG();
  }

  @failingTest
  @notForDart2
  test_export_configurations_useDefault() async {
    await super.test_export_configurations_useDefault();
  }

  @failingTest
  @notForDart2
  test_export_configurations_useFirst() async {
    await super.test_export_configurations_useFirst();
  }

  @failingTest
  @notForDart2
  test_export_configurations_useSecond() async {
    await super.test_export_configurations_useSecond();
  }

  @failingTest
  @notForDart2
  test_exportImport_configurations_useDefault() async {
    await super.test_exportImport_configurations_useDefault();
  }

  @failingTest
  @notForDart2
  test_exportImport_configurations_useFirst() async {
    await super.test_exportImport_configurations_useFirst();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_genericFunction_asGenericFunctionReturnType() async {
    await super.test_genericFunction_asGenericFunctionReturnType();
  }

  @failingTest
  @notForDart2
  test_import_configurations_useDefault() async {
    await super.test_import_configurations_useDefault();
  }

  @failingTest
  @notForDart2
  test_import_configurations_useFirst() async {
    await super.test_import_configurations_useFirst();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30725')
  test_import_invalidUri_metadata() async {
    await super.test_import_invalidUri_metadata();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30724')
  test_instantiateToBounds_boundRefersToEarlierTypeArgument() async {
    await super.test_instantiateToBounds_boundRefersToEarlierTypeArgument();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30724')
  test_instantiateToBounds_boundRefersToItself() async {
    await super.test_instantiateToBounds_boundRefersToItself();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30724')
  test_instantiateToBounds_boundRefersToLaterTypeArgument() async {
    await super.test_instantiateToBounds_boundRefersToLaterTypeArgument();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30724')
  test_instantiateToBounds_functionTypeAlias_simple() async {
    await super.test_instantiateToBounds_functionTypeAlias_simple();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30724')
  test_instantiateToBounds_simple() async {
    await super.test_instantiateToBounds_simple();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30267')
  test_invalid_annotation_prefixed_constructor() async {
    await super.test_invalid_annotation_prefixed_constructor();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30267')
  test_invalid_annotation_unprefixed_constructor() async {
    await super.test_invalid_annotation_unprefixed_constructor();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30267')
  test_invalid_nameConflict_imported() async {
    await super.test_invalid_nameConflict_imported();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30267')
  test_invalid_nameConflict_imported_exported() async {
    await super.test_invalid_nameConflict_imported_exported();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30267')
  test_invalid_nameConflict_local() async {
    await super.test_invalid_nameConflict_local();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30267')
  test_invalid_setterParameter_fieldFormalParameter() async {
    await super.test_invalid_setterParameter_fieldFormalParameter();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30725')
  test_invalidUri_part_emptyUri() async {
    await super.test_invalidUri_part_emptyUri();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30725')
  test_invalidUris() async {
    await super.test_invalidUris();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30284')
  test_metadata_exportDirective() async {
    await super.test_metadata_exportDirective();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30035')
  test_metadata_fieldFormalParameter() async {
    await super.test_metadata_fieldFormalParameter();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30035')
  test_metadata_fieldFormalParameter_withDefault() async {
    await super.test_metadata_fieldFormalParameter_withDefault();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30035')
  test_metadata_functionTypedFormalParameter() async {
    await super.test_metadata_functionTypedFormalParameter();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30035')
  test_metadata_functionTypedFormalParameter_withDefault() async {
    await super.test_metadata_functionTypedFormalParameter_withDefault();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30284')
  test_metadata_importDirective() async {
    await super.test_metadata_importDirective();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30267')
  test_metadata_invalid_classDeclaration() async {
    await super.test_metadata_invalid_classDeclaration();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30284')
  test_metadata_libraryDirective() async {
    await super.test_metadata_libraryDirective();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30284')
  test_metadata_partDirective() async {
    await super.test_metadata_partDirective();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30035')
  test_metadata_simpleFormalParameter() async {
    await super.test_metadata_simpleFormalParameter();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30035')
  test_metadata_simpleFormalParameter_withDefault() async {
    await super.test_metadata_simpleFormalParameter_withDefault();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_parameter_checked() async {
    await super.test_parameter_checked();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_parameter_checked_inherited() async {
    await super.test_parameter_checked_inherited();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30725')
  test_parts_invalidUri() async {
    await super.test_parts_invalidUri();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30725')
  test_parts_invalidUri_nullStringValue() async {
    await super.test_parts_invalidUri_nullStringValue();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_syntheticFunctionType_genericClosure() async {
    // TODO(scheglov): this does not work even in Analyzer
    await super.test_syntheticFunctionType_genericClosure();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_syntheticFunctionType_inGenericClass() async {
    // TODO(scheglov): this does not work even in Analyzer
    await super.test_syntheticFunctionType_inGenericClass();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_syntheticFunctionType_noArguments() async {
    // TODO(scheglov): this does not work even in Analyzer
    await super.test_syntheticFunctionType_noArguments();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_syntheticFunctionType_withArguments() async {
    // TODO(scheglov): this does not work even in Analyzer
    await super.test_syntheticFunctionType_withArguments();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_type_reference_to_typedef_with_type_arguments() async {
    // TODO(scheglov): triage
    await super.test_type_reference_to_typedef_with_type_arguments();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_type_reference_to_typedef_with_type_arguments_implicit() async {
    // TODO(scheglov): triage
    await super.test_type_reference_to_typedef_with_type_arguments_implicit();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_typedef_documented() async {
    // TODO(scheglov): implement
    await super.test_typedef_documented();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_typedef_generic() async {
    // TODO(scheglov): triage
    await super.test_typedef_generic();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_typedef_generic_asFieldType() async {
    // TODO(scheglov): triage
    await super.test_typedef_generic_asFieldType();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_typedef_type_parameters_bound() async {
    // TODO(scheglov): triage
    await super.test_typedef_type_parameters_bound();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30267')
  test_unresolved_annotation_instanceCreation_argument_super() async {
    await super.test_unresolved_annotation_instanceCreation_argument_super();
  }

  @failingTest
  @FastaProblem('https://github.com/dart-lang/sdk/issues/30267')
  test_unresolved_annotation_instanceCreation_argument_this() async {
    await super.test_unresolved_annotation_instanceCreation_argument_this();
  }

  @failingTest
  @potentialAnalyzerProblem
  test_unresolved_import() async {
    await super.test_unresolved_import();
  }

  String _getLibraryText(kernel.Library library) {
    StringBuffer buffer = new StringBuffer();
    new kernel.Printer(buffer, syntheticNames: new kernel.NameSystem())
        .writeLibraryFile(library);
    return buffer.toString();
  }
}

class _FileSystemAdaptor implements FileSystem {
  final ResourceProvider provider;

  _FileSystemAdaptor(this.provider);

  @override
  FileSystemEntity entityForUri(Uri uri) {
    if (uri.isScheme('file')) {
      var file = provider.getFile(uri.path);
      return new _FileSystemEntityAdaptor(uri, file);
    } else {
      throw new ArgumentError(
          'Only file:// URIs are supported, but $uri is given.');
    }
  }
}

class _FileSystemEntityAdaptor implements FileSystemEntity {
  final Uri uri;
  final File file;

  _FileSystemEntityAdaptor(this.uri, this.file);

  @override
  Future<bool> exists() async {
    return file.exists;
  }

  @override
  Future<List<int>> readAsBytes() async {
    return file.readAsBytesSync();
  }

  @override
  Future<String> readAsString() async {
    return file.readAsStringSync();
  }
}
