// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js.serialization_helper;

import 'dart:async';
import 'package:async_helper/async_helper.dart';
import 'package:expect/expect.dart';
import 'package:compiler/src/commandline_options.dart';
import 'package:compiler/src/common/backend_api.dart';
import 'package:compiler/src/common/names.dart';
import 'package:compiler/src/common/resolution.dart';
import 'package:compiler/src/compiler.dart';
import 'package:compiler/src/elements/elements.dart';
import 'package:compiler/src/filenames.dart';
import 'package:compiler/src/serialization/element_serialization.dart';
import 'package:compiler/src/serialization/impact_serialization.dart';
import 'package:compiler/src/serialization/json_serializer.dart';
import 'package:compiler/src/serialization/serialization.dart';
import 'package:compiler/src/serialization/task.dart';
import 'package:compiler/src/universe/world_impact.dart';
import 'memory_compiler.dart';


Future<String> serializeDartCore() async {
  Compiler compiler = compilerFor(
      options: [Flags.analyzeAll]);
  compiler.serialization.supportSerialization = true;
  await compiler.run(Uris.dart_core);
  return serialize(compiler, compiler.libraryLoader.libraries)
      .toText(const JsonSerializationEncoder());
}

Serializer serialize(Compiler compiler, Iterable<LibraryElement> libraries) {
  assert(compiler.serialization.supportSerialization);

  Serializer serializer = new Serializer();
  serializer.plugins.add(compiler.backend.serialization.serializer);
  serializer.plugins.add(new ResolutionImpactSerializer(compiler.resolution));

  for (LibraryElement library in libraries) {
    serializer.serialize(library);
  }
  return serializer;
}

void deserialize(Compiler compiler, String serializedData) {
  Deserializer deserializer = new Deserializer.fromText(
      new DeserializationContext(),
      serializedData,
      const JsonSerializationDecoder());
  deserializer.plugins.add(compiler.backend.serialization.deserializer);
  compiler.serialization.deserializer =
      new _DeserializerSystem(
          deserializer,
          compiler.backend.impactTransformer);
}


const String WORLD_IMPACT_TAG = 'worldImpact';

class ResolutionImpactSerializer extends SerializerPlugin {
  final Resolution resolution;

  ResolutionImpactSerializer(this.resolution);

  @override
  void onElement(Element element, ObjectEncoder createEncoder(String tag)) {
    if (resolution.hasBeenResolved(element)) {
      ResolutionImpact impact = resolution.getResolutionImpact(element);
      ObjectEncoder encoder = createEncoder(WORLD_IMPACT_TAG);
      new ImpactSerializer(encoder).serialize(impact);
    }
  }
}

class ResolutionImpactDeserializer extends DeserializerPlugin {
  Map<Element, ResolutionImpact> impactMap = <Element, ResolutionImpact>{};

  @override
  void onElement(Element element, ObjectDecoder getDecoder(String tag)) {
    ObjectDecoder decoder = getDecoder(WORLD_IMPACT_TAG);
    if (decoder != null) {
      impactMap[element] = ImpactDeserializer.deserializeImpact(decoder);
    }
  }
}

class _DeserializerSystem extends DeserializerSystem {
  final Deserializer _deserializer;
  final List<LibraryElement> deserializedLibraries = <LibraryElement>[];
  final ResolutionImpactDeserializer _resolutionImpactDeserializer =
      new ResolutionImpactDeserializer();
  final ImpactTransformer _impactTransformer;

  _DeserializerSystem(this._deserializer, this._impactTransformer) {
    _deserializer.plugins.add(_resolutionImpactDeserializer);
  }

  LibraryElement readLibrary(Uri resolvedUri) {
    LibraryElement library = _deserializer.lookupLibrary(resolvedUri);
    if (library != null) {
      deserializedLibraries.add(library);
    }
    return library;
  }

  ResolutionImpact getResolutionImpact(Element element) {
    return _resolutionImpactDeserializer.impactMap[element];
  }

  @override
  WorldImpact computeWorldImpact(Element element) {
    ResolutionImpact resolutionImpact = getResolutionImpact(element);
    if (resolutionImpact == null) {
      print('No impact found for $element (${element.library})');
      return const WorldImpact();
    } else {
      return _impactTransformer.transformResolutionImpact(resolutionImpact);
    }
  }

  @override
  bool isDeserialized(Element element) {
    return deserializedLibraries.contains(element.library);
  }
}
