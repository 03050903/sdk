// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer_cli.src.build_mode;

import 'dart:core' hide Resource;
import 'dart:io' as io;

import 'package:protobuf/protobuf.dart';

import 'package:analyzer/dart/ast/ast.dart' show CompilationUnit;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/java_io.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:analyzer/src/summary/format.dart';
import 'package:analyzer/src/summary/idl.dart';
import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:analyzer/src/summary/prelink.dart';
import 'package:analyzer/src/summary/summarize_ast.dart';
import 'package:analyzer/src/summary/summarize_elements.dart';
import 'package:analyzer/task/dart.dart';
import 'package:analyzer_cli/src/analyzer_impl.dart';
import 'package:analyzer_cli/src/driver.dart';
import 'package:analyzer_cli/src/error_formatter.dart';
import 'package:analyzer_cli/src/options.dart';

import 'message_grouper.dart';
import 'worker_protocol.pb.dart';

/**
 * Analyzer used when the "--build-mode" option is supplied.
 */
class BuildMode {
  final CommandLineOptions options;
  final AnalysisStats stats;

  final ResourceProvider resourceProvider = PhysicalResourceProvider.INSTANCE;
  SummaryDataStore summaryDataStore;
  InternalAnalysisContext context;
  Map<Uri, JavaFile> uriToFileMap;
  final List<Source> explicitSources = <Source>[];

  PackageBundleAssembler assembler = new PackageBundleAssembler();
  final Set<Source> processedSources = new Set<Source>();
  final Map<Uri, UnlinkedUnit> uriToUnit = <Uri, UnlinkedUnit>{};

  BuildMode(this.options, this.stats);

  /**
   * Perform package analysis according to the given [options].
   */
  ErrorSeverity analyze() {
    // Write initial progress message.
    if (!options.machineFormat) {
      outSink.writeln("Analyzing sources ${options.sourceFiles}...");
    }

    // Create the URI to file map.
    uriToFileMap = _createUriToFileMap(options.sourceFiles);
    if (uriToFileMap == null) {
      io.exitCode = ErrorSeverity.ERROR.ordinal;
      return ErrorSeverity.ERROR;
    }

    // Prepare the analysis context.
    _createContext();

    // Add sources.
    ChangeSet changeSet = new ChangeSet();
    for (Uri uri in uriToFileMap.keys) {
      JavaFile file = uriToFileMap[uri];
      if (!file.exists()) {
        errorSink.writeln('File not found: ${file.getPath()}');
        io.exitCode = ErrorSeverity.ERROR.ordinal;
        return ErrorSeverity.ERROR;
      }
      Source source = new FileBasedSource(file, uri);
      explicitSources.add(source);
      changeSet.addedSource(source);
    }
    context.applyChanges(changeSet);

    if (!options.buildSummaryOnly) {
      // Perform full analysis.
      while (true) {
        AnalysisResult analysisResult = context.performAnalysisTask();
        if (!analysisResult.hasMoreWork) {
          break;
        }
      }
    }

    // Write summary.
    if (options.buildSummaryOutput != null) {
      for (Source source in explicitSources) {
        if (context.computeKindOf(source) == SourceKind.LIBRARY) {
          if (options.buildSummaryFallback) {
            assembler.addFallbackLibrary(source);
          } else if (options.buildSummaryOnlyAst) {
            _serializeAstBasedSummary(source);
          } else {
            LibraryElement libraryElement =
                context.computeLibraryElement(source);
            assembler.serializeLibraryElement(libraryElement);
          }
        }
        if (options.buildSummaryFallback) {
          assembler.addFallbackUnit(source);
        }
      }
      // Write the whole package bundle.
      PackageBundleBuilder sdkBundle = assembler.assemble();
      if (options.buildSummaryExcludeInformative) {
        sdkBundle.flushInformative();
        sdkBundle.unlinkedUnitHashes = null;
      }
      io.File file = new io.File(options.buildSummaryOutput);
      file.writeAsBytesSync(sdkBundle.toBuffer(), mode: io.FileMode.WRITE_ONLY);
    }

    if (options.buildSummaryOnly) {
      return ErrorSeverity.NONE;
    } else {
      // Process errors.
      _printErrors(outputPath: options.buildAnalysisOutput);
      return _computeMaxSeverity();
    }
  }

  ErrorSeverity _computeMaxSeverity() {
    ErrorSeverity maxSeverity = ErrorSeverity.NONE;
    if (!options.buildSuppressExitCode) {
      for (Source source in explicitSources) {
        AnalysisErrorInfo errorInfo = context.getErrors(source);
        for (AnalysisError error in errorInfo.errors) {
          ProcessedSeverity processedSeverity =
              AnalyzerImpl.processError(error, options, context);
          if (processedSeverity != null) {
            maxSeverity = maxSeverity.max(processedSeverity.severity);
          }
        }
      }
    }
    return maxSeverity;
  }

  void _createContext() {
    DirectoryBasedDartSdk sdk =
        new DirectoryBasedDartSdk(new JavaFile(options.dartSdkPath));
    sdk.analysisOptions =
        Driver.createAnalysisOptionsForCommandLineOptions(options);
    sdk.useSummary = true;

    // Read the summaries.
    summaryDataStore = new SummaryDataStore(options.buildSummaryInputs);

    // In AST mode include SDK bundle to avoid parsing SDK sources.
    if (options.buildSummaryOnlyAst) {
      summaryDataStore.addBundle(null, sdk.getSummarySdkBundle());
    }

    // Create the context.
    context = AnalysisEngine.instance.createAnalysisContext();
    context.sourceFactory = new SourceFactory(<UriResolver>[
      new DartUriResolver(sdk),
      new InSummaryPackageUriResolver(summaryDataStore),
      new ExplicitSourceResolver(uriToFileMap)
    ]);

    // Set context options.
    Driver.setAnalysisContextOptions(context, options,
        (AnalysisOptionsImpl contextOptions) {
      if (options.buildSummaryOnlyDiet) {
        contextOptions.analyzeFunctionBodies = false;
      }
    });

    // Configure using summaries.
    context.typeProvider = sdk.context.typeProvider;
    context.resultProvider =
        new InputPackagesResultProvider(context, summaryDataStore);
  }

  /**
   * Print errors for all explicit sources.  If [outputPath] is supplied, output
   * is sent to a new file at that path.
   */
  void _printErrors({String outputPath}) {
    StringBuffer buffer = new StringBuffer();
    ErrorFormatter formatter = new ErrorFormatter(
        buffer,
        options,
        stats,
        (AnalysisError error) =>
            AnalyzerImpl.processError(error, options, context));
    for (Source source in explicitSources) {
      AnalysisErrorInfo errorInfo = context.getErrors(source);
      formatter.formatErrors([errorInfo]);
    }
    if (!options.machineFormat) {
      stats.print(buffer);
    }
    if (outputPath == null) {
      StringSink sink = options.machineFormat ? errorSink : outSink;
      sink.write(buffer);
    } else {
      new io.File(outputPath).writeAsStringSync(buffer.toString());
    }
  }

  /**
   * Serialize the library with the given [source] into [assembler] using only
   * its AST, [UnlinkedUnit]s of input packages and ASTs (via [UnlinkedUnit]s)
   * of package sources.
   */
  void _serializeAstBasedSummary(Source source) {
    Source resolveRelativeUri(String relativeUri) {
      Source resolvedSource =
          context.sourceFactory.resolveUri(source, relativeUri);
      if (resolvedSource == null) {
        context.sourceFactory.resolveUri(source, relativeUri);
        throw new StateError('Could not resolve $relativeUri in the context of '
            '$source (${source.runtimeType})');
      }
      return resolvedSource;
    }

    UnlinkedUnit _getUnlinkedUnit(Source source) {
      // Maybe an input package contains the source.
      {
        String uriStr = source.uri.toString();
        UnlinkedUnit unlinkedUnit = summaryDataStore.unlinkedMap[uriStr];
        if (unlinkedUnit != null) {
          return unlinkedUnit;
        }
      }
      // Parse the source and serialize its AST.
      return uriToUnit.putIfAbsent(source.uri, () {
        CompilationUnit unit = context.computeResult(source, PARSED_UNIT);
        UnlinkedUnitBuilder unlinkedUnit = serializeAstUnlinked(unit);
        assembler.addUnlinkedUnit(source, unlinkedUnit);
        return unlinkedUnit;
      });
    }

    UnlinkedUnit getPart(String relativeUri) {
      return _getUnlinkedUnit(resolveRelativeUri(relativeUri));
    }

    UnlinkedPublicNamespace getImport(String relativeUri) {
      return getPart(relativeUri).publicNamespace;
    }

    UnlinkedUnitBuilder definingUnit = _getUnlinkedUnit(source);
    LinkedLibraryBuilder linkedLibrary =
        prelink(definingUnit, getPart, getImport);
    assembler.addLinkedLibrary(source.uri.toString(), linkedLibrary);
  }

  /**
   * Convert [sourceEntities] (a list of file specifications of the form
   * "$uri|$path") to a map from URI to path.  If an error occurs, report the
   * error and return null.
   */
  static Map<Uri, JavaFile> _createUriToFileMap(List<String> sourceEntities) {
    Map<Uri, JavaFile> uriToFileMap = <Uri, JavaFile>{};
    for (String sourceFile in sourceEntities) {
      int pipeIndex = sourceFile.indexOf('|');
      if (pipeIndex == -1) {
        // TODO(paulberry): add the ability to guess the URI from the path.
        errorSink.writeln(
            'Illegal input file (must be "\$uri|\$path"): $sourceFile');
        return null;
      }
      Uri uri = Uri.parse(sourceFile.substring(0, pipeIndex));
      String path = sourceFile.substring(pipeIndex + 1);
      uriToFileMap[uri] = new JavaFile(path);
    }
    return uriToFileMap;
  }
}

/**
 * Connection between a worker and input / output.
 */
abstract class WorkerConnection {
  /**
   * Read a new [WorkRequest]. Returns [null] when there are no more requests.
   */
  WorkRequest readRequest();

  /**
   * Write the given [response] as bytes to the output.
   */
  void writeResponse(WorkResponse response);
}

/**
 * Persistent Bazel worker.
 */
class WorkerLoop {
  static const int EXIT_CODE_OK = 0;
  static const int EXIT_CODE_ERROR = 15;

  final WorkerConnection connection;

  final StringBuffer errorBuffer = new StringBuffer();
  final StringBuffer outBuffer = new StringBuffer();

  final String dartSdkPath;

  WorkerLoop(this.connection, {this.dartSdkPath});

  factory WorkerLoop.std(
      {io.Stdin stdinStream, io.Stdout stdoutStream, String dartSdkPath}) {
    stdinStream ??= io.stdin;
    stdoutStream ??= io.stdout;
    WorkerConnection connection =
        new StdWorkerConnection(stdinStream, stdoutStream);
    return new WorkerLoop(connection, dartSdkPath: dartSdkPath);
  }

  /**
   * Performs analysis with given [options].
   */
  void analyze(CommandLineOptions options) {
    options.dartSdkPath ??= dartSdkPath;
    new BuildMode(options, new AnalysisStats()).analyze();
  }

  /**
   * Perform a single loop step.  Return `true` if should exit the loop.
   */
  bool performSingle() {
    try {
      WorkRequest request = connection.readRequest();
      if (request == null) {
        return true;
      }
      // Prepare options.
      CommandLineOptions options =
          CommandLineOptions.parse(request.arguments, (String msg) {
        throw new ArgumentError(msg);
      });
      // Analyze and respond.
      analyze(options);
      String msg = _getErrorOutputBuffersText();
      connection.writeResponse(new WorkResponse()
        ..exitCode = EXIT_CODE_OK
        ..output = msg);
    } catch (e, st) {
      String msg = _getErrorOutputBuffersText();
      msg += '$e \n $st';
      connection.writeResponse(new WorkResponse()
        ..exitCode = EXIT_CODE_ERROR
        ..output = msg);
    }
    return false;
  }

  /**
   * Run the worker loop.
   */
  void run() {
    errorSink = errorBuffer;
    outSink = outBuffer;
    exitHandler = (int exitCode) {
      return throw new StateError('Exit called: $exitCode');
    };
    while (true) {
      errorBuffer.clear();
      outBuffer.clear();
      bool shouldExit = performSingle();
      if (shouldExit) {
        break;
      }
    }
  }

  String _getErrorOutputBuffersText() {
    String msg = '';
    if (errorBuffer.isNotEmpty) {
      msg += errorBuffer.toString() + '\n';
    }
    if (outBuffer.isNotEmpty) {
      msg += outBuffer.toString() + '\n';
    }
    return msg;
  }
}

/**
 * Default implementation of [WorkerConnection] that works with stdio.
 */
class StdWorkerConnection implements WorkerConnection {
  final MessageGrouper _messageGrouper;
  final io.Stdout _stdoutStream;

  StdWorkerConnection(io.Stdin stdinStream, this._stdoutStream)
      : _messageGrouper = new MessageGrouper(stdinStream);

  @override
  WorkRequest readRequest() {
    var buffer = _messageGrouper.next;
    if (buffer == null) return null;

    return new WorkRequest.fromBuffer(buffer);
  }

  @override
  void writeResponse(WorkResponse response) {
    var responseBuffer = response.writeToBuffer();

    var writer = new CodedBufferWriter();
    writer.writeInt32NoTag(responseBuffer.length);
    writer.writeRawBytes(responseBuffer);

    _stdoutStream.add(writer.toBuffer());
  }
}
