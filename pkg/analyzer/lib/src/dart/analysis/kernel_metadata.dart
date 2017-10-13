// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:front_end/src/fasta/kernel/metadata_collector.dart';
import 'package:front_end/src/incremental/kernel_driver.dart';
import 'package:kernel/kernel.dart' as kernel;

/// Additional information that Analyzer needs for nodes.
class AnalyzerMetadata {
  final kernel.Node parent;

  /// Optional documentation comment, may be `null`.
  String documentationComment;

  AnalyzerMetadata(this.parent);

  /// Return the [AnalyzerMetadata] for the [node], or `null` absent.
  static AnalyzerMetadata forNode(kernel.TreeNode node) {
    var repository =
        node.enclosingProgram.metadata[AnalyzerMetadataRepository.TAG];
    if (repository != null) {
      return repository.mapping[node];
    }
    return null;
  }
}

/// Analyzer specific implementation of [MetadataCollector].
class AnalyzerMetadataCollector implements MetadataCollector {
  @override
  final AnalyzerMetadataRepository repository =
      new AnalyzerMetadataRepository();

  @override
  void setDocumentationComment(kernel.NamedNode node, String comment) {
    var metadata = repository._forWriting(node);
    metadata.documentationComment = comment;
  }
}

/// Factory for creating Analyzer specific sink and repository.
class AnalyzerMetadataFactory implements MetadataFactory {
  @override
  int get version => 1;

  @override
  MetadataCollector newCollector() {
    return new AnalyzerMetadataCollector();
  }

  @override
  kernel.MetadataRepository newRepositoryForReading() {
    return new AnalyzerMetadataRepository();
  }
}

/// Analyzer specific implementation of [kernel.MetadataRepository].
class AnalyzerMetadataRepository
    implements kernel.MetadataRepository<AnalyzerMetadata> {
  static const TAG = 'kernel.metadata.analyzer';

  @override
  final String tag = TAG;

  @override
  final Map<kernel.Node, AnalyzerMetadata> mapping =
      <kernel.Node, AnalyzerMetadata>{};

  @override
  AnalyzerMetadata readFromBinary(kernel.BinarySource source) {
    var parent = source.readNodeReference();
    return new AnalyzerMetadata(parent)
      ..documentationComment = _readOptionalString(source);
  }

  @override
  void writeToBinary(AnalyzerMetadata metadata, kernel.BinarySink sink) {
    sink.writeNodeReference(metadata.parent);
    _writeOptionalString(sink, metadata.documentationComment);
  }

  /// Return the existing or new [AnalyzerMetadata] instance for the [node].
  AnalyzerMetadata _forWriting(kernel.Node node) {
    return mapping[node] ??= new AnalyzerMetadata(node);
  }

  String _readOptionalString(kernel.BinarySource source) {
    int flag = source.readByte();
    if (flag == 1) {
      List<int> bytes = source.readByteList();
      return UTF8.decode(bytes);
    } else {
      return null;
    }
  }

  void _writeOptionalString(kernel.BinarySink sink, String str) {
    if (str != null) {
      sink.writeByte(1);
      List<int> bytes = UTF8.encode(str);
      sink.writeByteList(bytes);
    } else {
      sink.writeByte(0);
    }
  }
}
