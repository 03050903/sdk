// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Equivalence test functions for data objects.

library dart2js.equivalence.functions;

import 'package:expect/expect.dart';
import 'package:compiler/src/common/resolution.dart';
import 'package:compiler/src/common_elements.dart';
import 'package:compiler/src/compiler.dart';
import 'package:compiler/src/elements/types.dart';
import 'package:compiler/src/elements/elements.dart';
import 'package:compiler/src/elements/entities.dart';
import 'package:compiler/src/enqueue.dart';
import 'package:compiler/src/js/js_debug.dart' as js;
import 'package:compiler/src/js_backend/backend.dart';
import 'package:compiler/src/js_backend/backend_usage.dart';
import 'package:compiler/src/js_backend/enqueuer.dart';
import 'package:compiler/src/js_backend/native_data.dart';
import 'package:compiler/src/js_backend/interceptor_data.dart';
import 'package:compiler/src/js_emitter/code_emitter_task.dart';
import 'package:compiler/src/js_emitter/model.dart';
import 'package:compiler/src/serialization/equivalence.dart';
import 'package:compiler/src/universe/class_set.dart';
import 'package:compiler/src/universe/world_builder.dart';
import 'package:compiler/src/util/util.dart';
import 'package:compiler/src/world.dart';
import 'package:js_ast/js_ast.dart' as js;
import 'check_helpers.dart';

void checkClosedWorlds(ClosedWorld closedWorld1, ClosedWorld closedWorld2,
    {TestStrategy strategy: const TestStrategy(),
    bool allowExtra: false,
    bool verbose: false,
    bool allowMissingClosureClasses: false}) {
  if (verbose) {
    print(closedWorld1.dump());
    print(closedWorld2.dump());
  }
  checkClassHierarchyNodes(
      closedWorld1,
      closedWorld2,
      closedWorld1
          .getClassHierarchyNode(closedWorld1.commonElements.objectClass),
      closedWorld2
          .getClassHierarchyNode(closedWorld2.commonElements.objectClass),
      strategy.elementEquivalence,
      verbose: verbose,
      allowMissingClosureClasses: allowMissingClosureClasses);

  checkNativeData(closedWorld1.nativeData, closedWorld2.nativeData,
      strategy: strategy, allowExtra: allowExtra, verbose: verbose);
  checkInterceptorData(closedWorld1.interceptorData,
      closedWorld2.interceptorData, strategy.elementEquivalence,
      verbose: verbose);
}

void checkNativeData(NativeDataImpl data1, NativeDataImpl data2,
    {TestStrategy strategy: const TestStrategy(),
    bool allowExtra: false,
    bool verbose: false}) {
  checkMapEquivalence(data1, data2, 'nativeMemberName', data1.nativeMemberName,
      data2.nativeMemberName, strategy.elementEquivalence, equality,
      allowExtra: allowExtra);

  checkMapEquivalence(
      data1,
      data2,
      'nativeMethodBehavior',
      data1.nativeMethodBehavior,
      data2.nativeMethodBehavior,
      strategy.elementEquivalence,
      (a, b) => testNativeBehavior(a, b, strategy: strategy),
      allowExtra: allowExtra);

  checkMapEquivalence(
      data1,
      data2,
      'nativeFieldLoadBehavior',
      data1.nativeFieldLoadBehavior,
      data2.nativeFieldLoadBehavior,
      strategy.elementEquivalence,
      (a, b) => testNativeBehavior(a, b, strategy: strategy),
      allowExtra: allowExtra);

  checkMapEquivalence(
      data1,
      data2,
      'nativeFieldStoreBehavior',
      data1.nativeFieldStoreBehavior,
      data2.nativeFieldStoreBehavior,
      strategy.elementEquivalence,
      (a, b) => testNativeBehavior(a, b, strategy: strategy),
      allowExtra: allowExtra);

  checkMapEquivalence(
      data1,
      data2,
      'jsInteropLibraryNames',
      data1.jsInteropLibraryNames,
      data2.jsInteropLibraryNames,
      strategy.elementEquivalence,
      equality);

  checkSetEquivalence(
      data1,
      data2,
      'anonymousJsInteropClasses',
      data1.anonymousJsInteropClasses,
      data2.anonymousJsInteropClasses,
      strategy.elementEquivalence);

  checkMapEquivalence(
      data1,
      data2,
      'jsInteropClassNames',
      data1.jsInteropClassNames,
      data2.jsInteropClassNames,
      strategy.elementEquivalence,
      equality);

  checkMapEquivalence(
      data1,
      data2,
      'jsInteropMemberNames',
      data1.jsInteropMemberNames,
      data2.jsInteropMemberNames,
      strategy.elementEquivalence,
      equality);
}

void checkInterceptorData(InterceptorDataImpl data1, InterceptorDataImpl data2,
    bool elementEquivalence(Entity a, Entity b),
    {bool verbose: false}) {
  checkMapEquivalence(
      data1,
      data2,
      'interceptedElements',
      data1.interceptedElementsForTesting,
      data2.interceptedElementsForTesting,
      equality,
      (a, b) => areSetsEquivalent(a, b, elementEquivalence));

  checkSetEquivalence(data1, data2, 'interceptedClasses',
      data1.interceptedClasses, data2.interceptedClasses, elementEquivalence);

  checkSetEquivalence(
      data1,
      data2,
      'classesMixedIntoInterceptedClasses',
      data1.classesMixedIntoInterceptedClassesForTesting,
      data2.classesMixedIntoInterceptedClassesForTesting,
      elementEquivalence);
}

void checkClassHierarchyNodes(
    ClosedWorld closedWorld1,
    ClosedWorld closedWorld2,
    ClassHierarchyNode node1,
    ClassHierarchyNode node2,
    bool elementEquivalence(Entity a, Entity b),
    {bool verbose: false,
    bool allowMissingClosureClasses: false}) {
  if (verbose) {
    print('Checking $node1 vs $node2');
  }
  ClassEntity cls1 = node1.cls;
  ClassEntity cls2 = node2.cls;
  Expect.isTrue(elementEquivalence(cls1, cls2),
      "Element identity mismatch for ${cls1} vs ${cls2}.");
  Expect.equals(
      node1.isDirectlyInstantiated,
      node2.isDirectlyInstantiated,
      "Value mismatch for 'isDirectlyInstantiated' "
      "for ${cls1} vs ${cls2}.");
  Expect.equals(
      node1.isIndirectlyInstantiated,
      node2.isIndirectlyInstantiated,
      "Value mismatch for 'isIndirectlyInstantiated' "
      "for ${node1.cls} vs ${node2.cls}.");
  // TODO(johnniwinther): Enforce a canonical and stable order on direct
  // subclasses.
  for (ClassHierarchyNode child in node1.directSubclasses) {
    bool found = false;
    for (ClassHierarchyNode other in node2.directSubclasses) {
      ClassEntity child1 = child.cls;
      ClassEntity child2 = other.cls;
      if (elementEquivalence(child1, child2)) {
        checkClassHierarchyNodes(
            closedWorld1, closedWorld2, child, other, elementEquivalence,
            verbose: verbose,
            allowMissingClosureClasses: allowMissingClosureClasses);
        found = true;
        break;
      }
    }
    if (!found && (!child.cls.isClosure || !allowMissingClosureClasses)) {
      if (child.isInstantiated) {
        print('Missing subclass ${child.cls} of ${node1.cls} '
            'in ${node2.directSubclasses}');
        print(closedWorld1.dump(
            verbose ? closedWorld1.commonElements.objectClass : node1.cls));
        print(closedWorld2.dump(
            verbose ? closedWorld2.commonElements.objectClass : node2.cls));
      }
      Expect.isFalse(
          child.isInstantiated,
          'Missing subclass ${child.cls} of ${node1.cls} in '
          '${node2.directSubclasses}');
    }
  }
  checkMixinUses(
      closedWorld1, closedWorld2, node1.cls, node2.cls, elementEquivalence,
      verbose: verbose);
  Expect.isNotNull(
      closedWorld1.getClassSet(cls1), "Missing ClassSet for $cls1");
  Expect.isNotNull(
      closedWorld2.getClassSet(cls2), "Missing ClassSet for $cls2");
}

void checkMixinUses(
    ClosedWorld closedWorld1,
    ClosedWorld closedWorld2,
    ClassEntity class1,
    ClassEntity class2,
    bool elementEquivalence(Entity a, Entity b),
    {bool verbose: false}) {
  checkSets(closedWorld1.mixinUsesOf(class1), closedWorld2.mixinUsesOf(class2),
      "Mixin uses of $class1 vs $class2", elementEquivalence,
      verbose: verbose);
}

/// Check member property equivalence between all members common to [compiler1]
/// and [compiler2].
void checkLoadedLibraryMembers(
    Compiler compiler1,
    Compiler compiler2,
    bool hasProperty(Element member1),
    void checkMemberProperties(Compiler compiler1, Element member1,
        Compiler compiler2, Element member2,
        {bool verbose}),
    {bool verbose: false}) {
  void checkMembers(Element member1, Element member2) {
    if (member1.isClass && member2.isClass) {
      ClassElement class1 = member1;
      ClassElement class2 = member2;
      if (!class1.isResolved) return;

      if (hasProperty(member1)) {
        if (areElementsEquivalent(member1, member2)) {
          checkMemberProperties(compiler1, member1, compiler2, member2,
              verbose: verbose);
        }
      }

      class1.forEachLocalMember((m1) {
        checkMembers(m1, class2.localLookup(m1.name));
      });
      ClassElement superclass1 = class1.superclass;
      ClassElement superclass2 = class2.superclass;
      while (superclass1 != null && superclass1.isUnnamedMixinApplication) {
        for (ConstructorElement c1 in superclass1.constructors) {
          checkMembers(c1, superclass2.lookupConstructor(c1.name));
        }
        superclass1 = superclass1.superclass;
        superclass2 = superclass2.superclass;
      }
      return;
    }

    if (!hasProperty(member1)) {
      return;
    }

    if (member2 == null) {
      throw 'Missing member for ${member1}';
    }

    if (areElementsEquivalent(member1, member2)) {
      checkMemberProperties(compiler1, member1, compiler2, member2,
          verbose: verbose);
    }
  }

  for (LibraryElement library1 in compiler1.libraryLoader.libraries) {
    LibraryElement library2 =
        compiler2.libraryLoader.lookupLibrary(library1.canonicalUri);
    if (library2 != null) {
      library1.forEachLocalMember((Element member1) {
        checkMembers(member1, library2.localLookup(member1.name));
      });
    }
  }
}

/// Check equivalence of all resolution impacts.
void checkAllImpacts(Compiler compiler1, Compiler compiler2,
    {bool verbose: false}) {
  checkLoadedLibraryMembers(compiler1, compiler2, (Element member1) {
    return compiler1.resolution.hasResolutionImpact(member1);
  }, checkImpacts, verbose: verbose);
}

/// Check equivalence of resolution impact for [member1] and [member2].
void checkImpacts(
    Compiler compiler1, Element member1, Compiler compiler2, Element member2,
    {bool verbose: false}) {
  ResolutionImpact impact1 = compiler1.resolution.getResolutionImpact(member1);
  ResolutionImpact impact2 = compiler2.resolution.getResolutionImpact(member2);

  if (impact1 == null && impact2 == null) return;

  if (verbose) {
    print('Checking impacts for $member1 vs $member2');
  }

  if (impact1 == null) {
    throw 'Missing impact for $member1. $member2 has $impact2';
  }
  if (impact2 == null) {
    throw 'Missing impact for $member2. $member1 has $impact1';
  }

  testResolutionImpactEquivalence(impact1, impact2,
      strategy: const CheckStrategy());
}

void checkAllResolvedAsts(Compiler compiler1, Compiler compiler2,
    {bool verbose: false}) {
  checkLoadedLibraryMembers(compiler1, compiler2, (Element member1) {
    return member1 is ExecutableElement &&
        compiler1.resolution.hasResolvedAst(member1);
  }, checkResolvedAsts, verbose: verbose);
}

/// Check equivalence of [impact1] and [impact2].
void checkResolvedAsts(
    Compiler compiler1, Element member1, Compiler compiler2, Element member2,
    {bool verbose: false}) {
  if (!compiler2.serialization.isDeserialized(member2)) {
    return;
  }
  ResolvedAst resolvedAst1 = compiler1.resolution.getResolvedAst(member1);
  ResolvedAst resolvedAst2 = compiler2.serialization.getResolvedAst(member2);

  if (resolvedAst1 == null || resolvedAst2 == null) return;

  if (verbose) {
    print('Checking resolved asts for $member1 vs $member2');
  }

  testResolvedAstEquivalence(resolvedAst1, resolvedAst2, const CheckStrategy());
}

void checkNativeClasses(
    Compiler compiler1, Compiler compiler2, TestStrategy strategy) {
  Iterable<ClassEntity> nativeClasses1 = compiler1
      .backend.nativeResolutionEnqueuerForTesting.nativeClassesForTesting;
  Iterable<ClassEntity> nativeClasses2 = compiler2
      .backend.nativeResolutionEnqueuerForTesting.nativeClassesForTesting;

  checkSetEquivalence(compiler1, compiler2, 'nativeClasses', nativeClasses1,
      nativeClasses2, strategy.elementEquivalence);

  Iterable<ClassEntity> registeredClasses1 = compiler1
      .backend.nativeResolutionEnqueuerForTesting.registeredClassesForTesting;
  Iterable<ClassEntity> registeredClasses2 = compiler2
      .backend.nativeResolutionEnqueuerForTesting.registeredClassesForTesting;

  checkSetEquivalence(compiler1, compiler2, 'registeredClasses',
      registeredClasses1, registeredClasses2, strategy.elementEquivalence);
}

void checkNativeBasicData(NativeBasicDataImpl data1, NativeBasicDataImpl data2,
    TestStrategy strategy) {
  checkMapEquivalence(
      data1,
      data2,
      'nativeClassTagInfo',
      data1.nativeClassTagInfo,
      data2.nativeClassTagInfo,
      strategy.elementEquivalence,
      (a, b) => a == b);
  // TODO(johnniwinther): Check the remaining properties.
}

void checkBackendUsage(
    BackendUsageImpl usage1, BackendUsageImpl usage2, TestStrategy strategy) {
  checkSetEquivalence(
      usage1,
      usage2,
      'globalClassDependencies',
      usage1.globalClassDependencies,
      usage2.globalClassDependencies,
      strategy.elementEquivalence);
  checkSetEquivalence(
      usage1,
      usage2,
      'globalFunctionDependencies',
      usage1.globalFunctionDependencies,
      usage2.globalFunctionDependencies,
      strategy.elementEquivalence);
  checkSetEquivalence(
      usage1,
      usage2,
      'helperClassesUsed',
      usage1.helperClassesUsed,
      usage2.helperClassesUsed,
      strategy.elementEquivalence);
  checkSetEquivalence(
      usage1,
      usage2,
      'helperFunctionsUsed',
      usage1.helperFunctionsUsed,
      usage2.helperFunctionsUsed,
      strategy.elementEquivalence);
  check(
      usage1,
      usage2,
      'needToInitializeIsolateAffinityTag',
      usage1.needToInitializeIsolateAffinityTag,
      usage2.needToInitializeIsolateAffinityTag);
  check(
      usage1,
      usage2,
      'needToInitializeDispatchProperty',
      usage1.needToInitializeDispatchProperty,
      usage2.needToInitializeDispatchProperty);
  check(usage1, usage2, 'requiresPreamble', usage1.requiresPreamble,
      usage2.requiresPreamble);
  check(usage1, usage2, 'isInvokeOnUsed', usage1.isInvokeOnUsed,
      usage2.isInvokeOnUsed);
  check(usage1, usage2, 'isRuntimeTypeUsed', usage1.isRuntimeTypeUsed,
      usage2.isRuntimeTypeUsed);
  check(usage1, usage2, 'isIsolateInUse', usage1.isIsolateInUse,
      usage2.isIsolateInUse);
  check(usage1, usage2, 'isFunctionApplyUsed', usage1.isFunctionApplyUsed,
      usage2.isFunctionApplyUsed);
  check(usage1, usage2, 'isNoSuchMethodUsed', usage1.isNoSuchMethodUsed,
      usage2.isNoSuchMethodUsed);
}

checkElementEnvironment(
    ElementEnvironment env1, ElementEnvironment env2, TestStrategy strategy) {
  strategy.testElements(
      env1, env2, 'mainLibrary', env1.mainLibrary, env2.mainLibrary);
  strategy.testElements(
      env1, env2, 'mainFunction', env1.mainFunction, env2.mainFunction);

  checkMembers(MemberEntity member1, MemberEntity member2) {
    Expect.equals(env1.isDeferredLoadLibraryGetter(member1),
        env2.isDeferredLoadLibraryGetter(member2));

    checkListEquivalence(
        member1,
        member2,
        'metadata',
        env1.getMemberMetadata(member1),
        env2.getMemberMetadata(member2),
        strategy.testConstantValues);
  }

  checkSetEquivalence(env1, env2, 'libraries', env1.libraries, env2.libraries,
      strategy.elementEquivalence,
      onSameElement: (LibraryEntity lib1, LibraryEntity lib2) {
    Expect.identical(lib1, env1.lookupLibrary(lib1.canonicalUri));
    Expect.identical(lib2, env2.lookupLibrary(lib2.canonicalUri));

    List<ClassEntity> classes2 = <ClassEntity>[];
    env1.forEachClass(lib1, (ClassEntity cls1) {
      Expect.identical(cls1, env1.lookupClass(lib1, cls1.name));

      String className = cls1.name;
      ClassEntity cls2 = env2.lookupClass(lib2, className);
      Expect.isNotNull(cls2, 'Missing class $className in $lib2');
      Expect.identical(cls2, env2.lookupClass(lib2, cls2.name));

      check(lib1, lib2, 'class:${className}', cls1, cls2,
          strategy.elementEquivalence);

      Expect.equals(env1.isGenericClass(cls1), env2.isGenericClass(cls2));

      check(
          cls1,
          cls2,
          'superclass',
          env1.getSuperClass(cls1, skipUnnamedMixinApplications: false),
          env2.getSuperClass(cls2, skipUnnamedMixinApplications: false),
          strategy.elementEquivalence);
      check(
          cls1,
          cls2,
          'superclass',
          env1.getSuperClass(cls1, skipUnnamedMixinApplications: true),
          env2.getSuperClass(cls2, skipUnnamedMixinApplications: true),
          strategy.elementEquivalence);

      List<InterfaceType> supertypes1 = <InterfaceType>[];
      env1.forEachSupertype(cls1, supertypes1.add);
      List<InterfaceType> supertypes2 = <InterfaceType>[];
      env2.forEachSupertype(cls2, supertypes1.add);
      strategy.testTypeLists(
          cls1, cls2, 'supertypes', supertypes1, supertypes2);

      List<ClassEntity> mixins1 = <ClassEntity>[];
      env1.forEachMixin(cls1, mixins1.add);
      List<ClassEntity> mixins2 = <ClassEntity>[];
      env2.forEachMixin(cls2, mixins2.add);
      strategy.testLists(
          cls1, cls2, 'mixins', mixins1, mixins2, strategy.elementEquivalence);

      Map<MemberEntity, ClassEntity> members1 = <MemberEntity, ClassEntity>{};
      Map<MemberEntity, ClassEntity> members2 = <MemberEntity, ClassEntity>{};
      env1.forEachClassMember(cls1,
          (ClassEntity declarer1, MemberEntity member1) {
        if (cls1 == declarer1) {
          Expect.identical(
              member1,
              env1.lookupClassMember(cls1, member1.name,
                  setter: member1.isSetter));
        }
        members1[member1] = declarer1;
      });
      env2.forEachClassMember(cls2,
          (ClassEntity declarer2, MemberEntity member2) {
        if (cls2 == declarer2) {
          Expect.identical(
              member2,
              env2.lookupClassMember(cls2, member2.name,
                  setter: member2.isSetter));
        }
        members2[member2] = declarer2;
      });
      checkMapEquivalence(cls1, cls2, 'members', members1, members2, (a, b) {
        bool result = strategy.elementEquivalence(a, b);
        if (result) checkMembers(a, b);
        return result;
      }, strategy.elementEquivalence);

      Set<ConstructorEntity> constructors2 = new Set<ConstructorEntity>();
      env1.forEachConstructor(cls1, (ConstructorEntity constructor1) {
        Expect.identical(
            constructor1, env1.lookupConstructor(cls1, constructor1.name));

        String constructorName = constructor1.name;
        ConstructorEntity constructor2 =
            env2.lookupConstructor(cls2, constructorName);
        Expect.isNotNull(
            constructor2, "Missing constructor for $constructor1 in $cls2 ");
        Expect.identical(
            constructor2, env2.lookupConstructor(cls2, constructor2.name));

        constructors2.add(constructor2);

        check(cls1, cls2, 'constructor:${constructorName}', constructor1,
            constructor2, strategy.elementEquivalence);

        checkMembers(constructor1, constructor2);
      });
      env2.forEachConstructor(cls2, (ConstructorEntity constructor2) {
        Expect.isTrue(constructors2.contains(constructor2),
            "Extra constructor $constructor2 in $cls2");
      });

      classes2.add(cls2);
    });
    env2.forEachClass(lib2, (ClassEntity cls2) {
      Expect.isTrue(classes2.contains(cls2), "Extra class $cls2 in $lib2");
    });

    Set<MemberEntity> members2 = new Set<MemberEntity>();
    env1.forEachLibraryMember(lib1, (MemberEntity member1) {
      Expect.identical(
          member1,
          env1.lookupLibraryMember(lib1, member1.name,
              setter: member1.isSetter));

      String memberName = member1.name;
      MemberEntity member2 =
          env2.lookupLibraryMember(lib2, memberName, setter: member1.isSetter);
      Expect.isNotNull(member2, 'Missing member for $member1 in $lib2');
      Expect.identical(
          member2,
          env2.lookupLibraryMember(lib2, member2.name,
              setter: member2.isSetter));

      members2.add(member2);

      check(lib1, lib2, 'member:${memberName}', member1, member2,
          strategy.elementEquivalence);

      checkMembers(member1, member2);
    });
    env2.forEachLibraryMember(lib2, (MemberEntity member2) {
      Expect.isTrue(
          members2.contains(member2), "Extra member $member2 in $lib2");
    });
  });
  // TODO(johnniwinther): Test the remaining properties of [ElementEnvironment].
}

bool areInstantiationInfosEquivalent(
    InstantiationInfo info1,
    InstantiationInfo info2,
    bool elementEquivalence(Entity a, Entity b),
    bool typeEquivalence(DartType a, DartType b)) {
  checkMaps(
      info1.instantiationMap,
      info2.instantiationMap,
      'instantiationMap of\n   '
      '${info1.instantiationMap}\nvs ${info2.instantiationMap}',
      elementEquivalence,
      (a, b) => areSetsEquivalent(
          a, b, (a, b) => areInstancesEquivalent(a, b, typeEquivalence)));
  return true;
}

bool areInstancesEquivalent(Instance instance1, Instance instance2,
    bool typeEquivalence(DartType a, DartType b)) {
  InterfaceType type1 = instance1.type;
  InterfaceType type2 = instance2.type;
  return typeEquivalence(type1, type2) &&
      instance1.kind == instance2.kind &&
      instance1.isRedirection == instance2.isRedirection;
}

bool areAbstractUsagesEquivalent(AbstractUsage usage1, AbstractUsage usage2) {
  return usage1.hasSameUsage(usage2);
}

bool _areEntitiesEquivalent(a, b) => areElementsEquivalent(a, b);

void checkResolutionEnqueuers(
    BackendUsage backendUsage1,
    BackendUsage backendUsage2,
    ResolutionEnqueuer enqueuer1,
    ResolutionEnqueuer enqueuer2,
    {bool elementEquivalence(Entity a, Entity b): _areEntitiesEquivalent,
    bool typeEquivalence(DartType a, DartType b): areTypesEquivalent,
    bool elementFilter(Entity element),
    bool verbose: false,
    bool skipClassUsageTesting: false}) {
  elementFilter ??= (_) => true;

  ResolutionWorldBuilderBase worldBuilder1 = enqueuer1.worldBuilder;
  ResolutionWorldBuilderBase worldBuilder2 = enqueuer2.worldBuilder;

  checkSets(worldBuilder1.instantiatedTypes, worldBuilder2.instantiatedTypes,
      "Instantiated types mismatch", typeEquivalence,
      verbose: verbose);

  checkSets(
      worldBuilder1.directlyInstantiatedClasses,
      worldBuilder2.directlyInstantiatedClasses,
      "Directly instantiated classes mismatch",
      elementEquivalence,
      verbose: verbose);

  checkMaps(
      worldBuilder1.getInstantiationMap(),
      worldBuilder2.getInstantiationMap(),
      "Instantiated classes mismatch",
      elementEquivalence,
      (a, b) => areInstantiationInfosEquivalent(
          a, b, elementEquivalence, typeEquivalence),
      verbose: verbose);

  checkSets(enqueuer1.processedEntities, enqueuer2.processedEntities,
      "Processed element mismatch", elementEquivalence,
      elementFilter: elementFilter, verbose: verbose);

  checkSets(worldBuilder1.isChecks, worldBuilder2.isChecks, "Is-check mismatch",
      typeEquivalence,
      verbose: verbose);

  checkSets(worldBuilder1.closurizedMembers, worldBuilder2.closurizedMembers,
      "closurizedMembers", elementEquivalence,
      verbose: verbose);
  checkSets(worldBuilder1.fieldSetters, worldBuilder2.fieldSetters,
      "fieldSetters", elementEquivalence,
      verbose: verbose);
  checkSets(
      worldBuilder1.methodsNeedingSuperGetter,
      worldBuilder2.methodsNeedingSuperGetter,
      "methodsNeedingSuperGetter",
      elementEquivalence,
      verbose: verbose);

  if (!skipClassUsageTesting) {
    checkMaps(
        worldBuilder1.classUsageForTesting,
        worldBuilder2.classUsageForTesting,
        'classUsageForTesting',
        elementEquivalence,
        areAbstractUsagesEquivalent,
        verbose: verbose);
  }
  checkMaps(
      worldBuilder1.staticMemberUsageForTesting,
      worldBuilder2.staticMemberUsageForTesting,
      'staticMemberUsageForTesting',
      elementEquivalence,
      areAbstractUsagesEquivalent,
      keyFilter: elementFilter,
      verbose: verbose);
  checkMaps(
      worldBuilder1.instanceMemberUsageForTesting,
      worldBuilder2.instanceMemberUsageForTesting,
      'instanceMemberUsageForTesting',
      elementEquivalence,
      areAbstractUsagesEquivalent,
      verbose: verbose);

  Expect.equals(backendUsage1.isInvokeOnUsed, backendUsage2.isInvokeOnUsed,
      "JavaScriptBackend.hasInvokeOnSupport mismatch");
  Expect.equals(
      backendUsage1.isFunctionApplyUsed,
      backendUsage1.isFunctionApplyUsed,
      "JavaScriptBackend.hasFunctionApplySupport mismatch");
  Expect.equals(
      backendUsage1.isRuntimeTypeUsed,
      backendUsage2.isRuntimeTypeUsed,
      "JavaScriptBackend.hasRuntimeTypeSupport mismatch");
  Expect.equals(backendUsage1.isIsolateInUse, backendUsage2.isIsolateInUse,
      "JavaScriptBackend.hasIsolateSupport mismatch");
}

void checkCodegenEnqueuers(CodegenEnqueuer enqueuer1, CodegenEnqueuer enqueuer2,
    {bool elementEquivalence(Entity a, Entity b): _areEntitiesEquivalent,
    bool typeEquivalence(DartType a, DartType b): areTypesEquivalent,
    bool elementFilter(Element element),
    bool verbose: false}) {
  CodegenWorldBuilderImpl worldBuilder1 = enqueuer1.worldBuilder;
  CodegenWorldBuilderImpl worldBuilder2 = enqueuer2.worldBuilder;

  checkSets(worldBuilder1.instantiatedTypes, worldBuilder2.instantiatedTypes,
      "Instantiated types mismatch", typeEquivalence,
      verbose: verbose);

  checkSets(
      worldBuilder1.directlyInstantiatedClasses,
      worldBuilder2.directlyInstantiatedClasses,
      "Directly instantiated classes mismatch",
      elementEquivalence,
      verbose: verbose);

  checkSets(enqueuer1.processedEntities, enqueuer2.processedEntities,
      "Processed element mismatch", elementEquivalence, elementFilter: (e) {
    return elementFilter != null ? elementFilter(e) : true;
  }, verbose: verbose);

  checkSets(worldBuilder1.isChecks, worldBuilder2.isChecks, "Is-check mismatch",
      typeEquivalence,
      verbose: verbose);

  checkSets(
      worldBuilder1.allReferencedStaticFields,
      worldBuilder2.allReferencedStaticFields,
      "Directly instantiated classes mismatch",
      elementEquivalence,
      verbose: verbose);
  checkSets(worldBuilder1.closurizedMembers, worldBuilder2.closurizedMembers,
      "closurizedMembers", elementEquivalence,
      verbose: verbose);
  checkSets(worldBuilder1.processedClasses, worldBuilder2.processedClasses,
      "processedClasses", elementEquivalence,
      verbose: verbose);
  checkSets(
      worldBuilder1.methodsNeedingSuperGetter,
      worldBuilder2.methodsNeedingSuperGetter,
      "methodsNeedingSuperGetter",
      elementEquivalence,
      verbose: verbose);
  checkSets(
      worldBuilder1.staticFunctionsNeedingGetter,
      worldBuilder2.staticFunctionsNeedingGetter,
      "staticFunctionsNeedingGetter",
      elementEquivalence,
      verbose: verbose);

  checkMaps(
      worldBuilder1.classUsageForTesting,
      worldBuilder2.classUsageForTesting,
      'classUsageForTesting',
      elementEquivalence,
      areAbstractUsagesEquivalent,
      verbose: verbose);
  checkMaps(
      worldBuilder1.staticMemberUsageForTesting,
      worldBuilder2.staticMemberUsageForTesting,
      'staticMemberUsageForTesting',
      elementEquivalence,
      areAbstractUsagesEquivalent,
      verbose: verbose);
  checkMaps(
      worldBuilder1.instanceMemberUsageForTesting,
      worldBuilder2.instanceMemberUsageForTesting,
      'instanceMemberUsageForTesting',
      elementEquivalence,
      areAbstractUsagesEquivalent,
      verbose: verbose);
}

// TODO(johnniwinther): Check all emitter properties.
void checkEmitters(CodeEmitterTask emitter1, CodeEmitterTask emitter2,
    {bool elementEquivalence(Entity a, Entity b): _areEntitiesEquivalent,
    bool typeEquivalence(DartType a, DartType b): areTypesEquivalent,
    bool elementFilter(Element element),
    bool verbose: false}) {
  checkEmitterPrograms(
      emitter1.emitter.programForTesting, emitter2.emitter.programForTesting);

  checkSets(
      emitter1.typeTestRegistry.rtiNeededClasses,
      emitter2.typeTestRegistry.rtiNeededClasses,
      "TypeTestRegistry rti needed classes mismatch",
      elementEquivalence,
      verbose: verbose);

  checkSets(
      emitter1.typeTestRegistry.checkedFunctionTypes,
      emitter2.typeTestRegistry.checkedFunctionTypes,
      "TypeTestRegistry checked function types mismatch",
      typeEquivalence,
      verbose: verbose);

  checkSets(
      emitter1.typeTestRegistry.checkedClasses,
      emitter2.typeTestRegistry.checkedClasses,
      "TypeTestRegistry checked classes mismatch",
      elementEquivalence,
      verbose: verbose);
}

// TODO(johnniwinther): Check all program properties.
void checkEmitterPrograms(Program program1, Program program2) {
  checkLists(program1.fragments, program2.fragments, 'fragments',
      (a, b) => a.outputFileName == b.outputFileName,
      onSameElement: checkEmitterFragments);
}

// TODO(johnniwinther): Check all fragment properties.
void checkEmitterFragments(Fragment fragment1, Fragment fragment2) {
  checkLists(fragment1.libraries, fragment2.libraries, 'libraries',
      (a, b) => a.element.canonicalUri == b.element.canonicalUri,
      onSameElement: checkEmitterLibraries);
}

// TODO(johnniwinther): Check all library properties.
void checkEmitterLibraries(Library library1, Library library2) {
  checkLists(library1.classes, library2.classes, 'classes',
      (a, b) => a.element.name == b.element.name,
      onSameElement: checkEmitterClasses);
  // TODO(johnniwinther): Check static method properties.
  checkLists(library1.statics, library2.statics, 'statics',
      (a, b) => a.name.key == b.name.key);
}

// TODO(johnniwinther): Check all class properties.
void checkEmitterClasses(Class class1, Class class2) {
  checkLists(class1.methods, class2.methods, 'methods',
      (a, b) => a.name.key == b.name.key);
  checkLists(class1.isChecks, class2.isChecks, 'isChecks',
      (a, b) => a.name.key == b.name.key);
}

void checkGeneratedCode(JavaScriptBackend backend1, JavaScriptBackend backend2,
    {bool elementEquivalence(Entity a, Entity b): _areEntitiesEquivalent}) {
  checkMaps(backend1.generatedCode, backend2.generatedCode, 'generatedCode',
      elementEquivalence, areJsNodesEquivalent,
      valueToString: js.nodeToString);
}

bool areJsNodesEquivalent(js.Node node1, js.Node node2) {
  return new JsEquivalenceVisitor().testNodes(node1, node2);
}

class JsEquivalenceVisitor implements js.NodeVisitor<bool> {
  Link<js.Node> stack1 = const Link<js.Node>();
  Link<js.Node> stack2 = const Link<js.Node>();
  Map<String, String> labelsMap = <String, String>{};

  void push(js.Node node1, js.Node node2) {
    stack1 = stack1.prepend(node1);
    stack2 = stack2.prepend(node2);
  }

  js.Node peek() => stack2.head;

  void pop() {
    stack1 = stack1.tail;
    stack2 = stack2.tail;
  }

  bool failAt(js.Node node1, js.Node node2) {
    print('Node mismatch:');
    print('  ${js.nodeToString(node1)}');
    print('  ${js.nodeToString(node2)}');
    return false;
  }

  bool testValues(Object object1, Object object2) {
    if (object1 != object2) {
      print('Value mismatch:');
      print('  ${object1}');
      print('  ${object2}');
      print('at');
      print('  ${js.nodeToString(stack1.head)}');
      print('  ${js.nodeToString(stack2.head)}');
    }
    return object1 == object2;
  }

  bool testLabels(String object1, String object2) {
    if (object1 == null && object2 == null) return true;
    if (labelsMap.containsKey(object1)) {
      String expectedValue = labelsMap[object1];
      if (expectedValue != object2) {
        print('Value mismatch:');
        print('  ${object1}');
        print('  found ${object2}, expected ${expectedValue}');
        print('at');
        print('  ${js.nodeToString(stack1.head)}');
        print('  ${js.nodeToString(stack2.head)}');
      }
      return expectedValue == object2;
    } else {
      labelsMap[object1] = object2;
      return true;
    }
  }

  bool testNodes(js.Node node1, js.Node node2) {
    if (identical(node1, node2)) return true;
    if (node1 == null || node2 == null) return failAt(node1, node2);
    push(node1, node2);
    bool result = node1.accept(this);
    pop();
    return result;
  }

  bool testNodeLists(List<js.Node> list1, List<js.Node> list2) {
    int index = 0;
    while (index < list1.length && index < list2.length) {
      if (!testNodes(list1[index], list2[index])) return false;
      index++;
    }
    if (index < list1.length) {
      return failAt(list1[index], null);
    } else if (index < list2.length) {
      return failAt(list2[index], null);
    }
    return true;
  }

  @override
  bool visitProgram(js.Program node) {
    if (peek() is! js.Program) return failAt(node, peek());
    js.Program other = peek();
    return testNodeLists(node.body, other.body);
  }

  @override
  bool visitInterpolatedDeclaration(js.InterpolatedDeclaration node) {
    if (peek() is! js.InterpolatedDeclaration) return failAt(node, peek());
    js.InterpolatedDeclaration other = peek();
    return testValues(node.nameOrPosition, other.nameOrPosition);
  }

  @override
  bool visitInterpolatedStatement(js.InterpolatedStatement node) {
    if (peek() is! js.InterpolatedStatement) return failAt(node, peek());
    js.InterpolatedStatement other = peek();
    return testValues(node.nameOrPosition, other.nameOrPosition);
  }

  @override
  bool visitInterpolatedSelector(js.InterpolatedSelector node) {
    if (peek() is! js.InterpolatedSelector) return failAt(node, peek());
    js.InterpolatedSelector other = peek();
    return testValues(node.nameOrPosition, other.nameOrPosition);
  }

  @override
  bool visitInterpolatedParameter(js.InterpolatedParameter node) {
    if (peek() is! js.InterpolatedParameter) return failAt(node, peek());
    js.InterpolatedParameter other = peek();
    return testValues(node.nameOrPosition, other.nameOrPosition);
  }

  @override
  bool visitInterpolatedLiteral(js.InterpolatedLiteral node) {
    if (peek() is! js.InterpolatedLiteral) return failAt(node, peek());
    js.InterpolatedLiteral other = peek();
    return testValues(node.nameOrPosition, other.nameOrPosition);
  }

  @override
  bool visitInterpolatedExpression(js.InterpolatedExpression node) {
    if (peek() is! js.InterpolatedExpression) return failAt(node, peek());
    js.InterpolatedExpression other = peek();
    return testValues(node.nameOrPosition, other.nameOrPosition);
  }

  @override
  bool visitComment(js.Comment node) {
    if (peek() is! js.Comment) return failAt(node, peek());
    js.Comment other = peek();
    return testValues(node.comment, other.comment);
  }

  @override
  bool visitAwait(js.Await node) {
    if (peek() is! js.Await) return failAt(node, peek());
    js.Await other = peek();
    return testNodes(node.expression, other.expression);
  }

  @override
  bool visitRegExpLiteral(js.RegExpLiteral node) {
    if (peek() is! js.RegExpLiteral) return failAt(node, peek());
    js.RegExpLiteral other = peek();
    return testValues(node.pattern, other.pattern);
  }

  @override
  bool visitProperty(js.Property node) {
    if (peek() is! js.Property) return failAt(node, peek());
    js.Property other = peek();
    return testNodes(node.name, other.name) &&
        testNodes(node.value, other.value);
  }

  @override
  bool visitObjectInitializer(js.ObjectInitializer node) {
    if (peek() is! js.ObjectInitializer) return failAt(node, peek());
    js.ObjectInitializer other = peek();
    return testNodeLists(node.properties, other.properties);
  }

  @override
  bool visitArrayHole(js.ArrayHole node) {
    if (peek() is! js.ArrayHole) return failAt(node, peek());
    return true;
  }

  @override
  bool visitArrayInitializer(js.ArrayInitializer node) {
    if (peek() is! js.ArrayInitializer) return failAt(node, peek());
    js.ArrayInitializer other = peek();
    return testNodeLists(node.elements, other.elements);
  }

  @override
  bool visitName(js.Name node) {
    if (peek() is! js.Name) return failAt(node, peek());
    js.Name other = peek();
    return testValues(node.key, other.key);
  }

  @override
  bool visitStringConcatenation(js.StringConcatenation node) {
    if (peek() is! js.StringConcatenation) return failAt(node, peek());
    js.StringConcatenation other = peek();
    return testNodeLists(node.parts, other.parts);
  }

  @override
  bool visitLiteralNull(js.LiteralNull node) {
    if (peek() is! js.LiteralNull) return failAt(node, peek());
    return true;
  }

  @override
  bool visitLiteralNumber(js.LiteralNumber node) {
    if (peek() is! js.LiteralNumber) return failAt(node, peek());
    js.LiteralNumber other = peek();
    return testValues(node.value, other.value);
  }

  @override
  bool visitLiteralString(js.LiteralString node) {
    if (peek() is! js.LiteralString) return failAt(node, peek());
    js.LiteralString other = peek();
    return testValues(node.value, other.value);
  }

  @override
  bool visitLiteralBool(js.LiteralBool node) {
    if (peek() is! js.LiteralBool) return failAt(node, peek());
    js.LiteralBool other = peek();
    return testValues(node.value, other.value);
  }

  @override
  bool visitDeferredString(js.DeferredString node) {
    if (peek() is! js.DeferredString) return failAt(node, peek());
    js.DeferredString other = peek();
    return testValues(node.value, other.value);
  }

  @override
  bool visitDeferredNumber(js.DeferredNumber node) {
    if (peek() is! js.DeferredNumber) return failAt(node, peek());
    js.DeferredNumber other = peek();
    return testValues(node.value, other.value);
  }

  @override
  bool visitDeferredExpression(js.DeferredExpression node) {
    if (peek() is! js.DeferredExpression) return failAt(node, peek());
    js.DeferredExpression other = peek();
    return testNodes(node.value, other.value);
  }

  @override
  bool visitFun(js.Fun node) {
    if (peek() is! js.Fun) return failAt(node, peek());
    js.Fun other = peek();
    return testNodeLists(node.params, other.params) &&
        testNodes(node.body, other.body) &&
        testValues(node.asyncModifier, other.asyncModifier);
  }

  @override
  bool visitNamedFunction(js.NamedFunction node) {
    if (peek() is! js.NamedFunction) return failAt(node, peek());
    js.NamedFunction other = peek();
    return testNodes(node.name, other.name) &&
        testNodes(node.function, other.function);
  }

  @override
  bool visitAccess(js.PropertyAccess node) {
    if (peek() is! js.PropertyAccess) return failAt(node, peek());
    js.PropertyAccess other = peek();
    return testNodes(node.receiver, other.receiver) &&
        testNodes(node.selector, other.selector);
  }

  @override
  bool visitParameter(js.Parameter node) {
    if (peek() is! js.Parameter) return failAt(node, peek());
    js.Parameter other = peek();
    return testValues(node.name, other.name);
  }

  @override
  bool visitVariableDeclaration(js.VariableDeclaration node) {
    if (peek() is! js.VariableDeclaration) return failAt(node, peek());
    js.VariableDeclaration other = peek();
    return testValues(node.name, other.name) &&
        testValues(node.allowRename, other.allowRename);
  }

  @override
  bool visitThis(js.This node) {
    if (peek() is! js.This) return failAt(node, peek());
    return true;
  }

  @override
  bool visitVariableUse(js.VariableUse node) {
    if (peek() is! js.VariableUse) return failAt(node, peek());
    js.VariableUse other = peek();
    return testValues(node.name, other.name);
  }

  @override
  bool visitPostfix(js.Postfix node) {
    if (peek() is! js.Postfix) return failAt(node, peek());
    js.Postfix other = peek();
    return testValues(node.op, other.op) &&
        testNodes(node.argument, other.argument);
  }

  @override
  bool visitPrefix(js.Prefix node) {
    if (peek() is! js.Prefix) return failAt(node, peek());
    js.Prefix other = peek();
    return testValues(node.op, other.op) &&
        testNodes(node.argument, other.argument);
  }

  @override
  bool visitBinary(js.Binary node) {
    if (peek() is! js.Binary) return failAt(node, peek());
    js.Binary other = peek();
    return testNodes(node.left, other.left) &&
        testValues(node.op, other.op) &&
        testNodes(node.right, other.right);
  }

  @override
  bool visitCall(js.Call node) {
    if (peek() is! js.Call) return failAt(node, peek());
    js.Call other = peek();
    return testNodes(node.target, other.target) &&
        testNodeLists(node.arguments, other.arguments);
  }

  @override
  bool visitNew(js.New node) {
    if (peek() is! js.New) return failAt(node, peek());
    js.New other = peek();
    return testNodes(node.target, other.target) &&
        testNodeLists(node.arguments, other.arguments);
  }

  @override
  bool visitConditional(js.Conditional node) {
    if (peek() is! js.Conditional) return failAt(node, peek());
    js.Conditional other = peek();
    return testNodes(node.condition, other.condition) &&
        testNodes(node.then, other.then) &&
        testNodes(node.otherwise, other.otherwise);
  }

  @override
  bool visitVariableInitialization(js.VariableInitialization node) {
    if (peek() is! js.VariableInitialization) return failAt(node, peek());
    js.VariableInitialization other = peek();
    return testNodes(node.declaration, other.declaration) &&
        testNodes(node.leftHandSide, other.leftHandSide) &&
        testValues(node.op, other.op) &&
        testNodes(node.value, other.value);
  }

  @override
  bool visitAssignment(js.Assignment node) {
    if (peek() is! js.Assignment) return failAt(node, peek());
    js.Assignment other = peek();
    return testNodes(node.leftHandSide, other.leftHandSide) &&
        testValues(node.op, other.op) &&
        testNodes(node.value, other.value);
  }

  @override
  bool visitVariableDeclarationList(js.VariableDeclarationList node) {
    if (peek() is! js.VariableDeclarationList) return failAt(node, peek());
    js.VariableDeclarationList other = peek();
    return testNodeLists(node.declarations, other.declarations);
  }

  @override
  bool visitLiteralExpression(js.LiteralExpression node) {
    if (peek() is! js.LiteralExpression) return failAt(node, peek());
    js.LiteralExpression other = peek();
    return testValues(node.template, other.template) &&
        testNodeLists(node.inputs, other.inputs);
  }

  @override
  bool visitDartYield(js.DartYield node) {
    if (peek() is! js.DartYield) return failAt(node, peek());
    js.DartYield other = peek();
    return testNodes(node.expression, other.expression) &&
        testValues(node.hasStar, other.hasStar);
  }

  @override
  bool visitLiteralStatement(js.LiteralStatement node) {
    if (peek() is! js.LiteralStatement) return failAt(node, peek());
    js.LiteralStatement other = peek();
    return testValues(node.code, other.code);
  }

  @override
  bool visitLabeledStatement(js.LabeledStatement node) {
    if (peek() is! js.LabeledStatement) return failAt(node, peek());
    js.LabeledStatement other = peek();
    return testLabels(node.label, other.label) &&
        testNodes(node.body, other.body);
  }

  @override
  bool visitFunctionDeclaration(js.FunctionDeclaration node) {
    if (peek() is! js.FunctionDeclaration) return failAt(node, peek());
    js.FunctionDeclaration other = peek();
    return testNodes(node.name, other.name) &&
        testNodes(node.function, other.function);
  }

  @override
  bool visitDefault(js.Default node) {
    if (peek() is! js.Default) return failAt(node, peek());
    js.Default other = peek();
    return testNodes(node.body, other.body);
  }

  @override
  bool visitCase(js.Case node) {
    if (peek() is! js.Case) return failAt(node, peek());
    js.Case other = peek();
    return testNodes(node.expression, other.expression) &&
        testNodes(node.body, other.body);
  }

  @override
  bool visitSwitch(js.Switch node) {
    if (peek() is! js.Switch) return failAt(node, peek());
    js.Switch other = peek();
    return testNodes(node.key, other.key) &&
        testNodeLists(node.cases, other.cases);
  }

  @override
  bool visitCatch(js.Catch node) {
    if (peek() is! js.Catch) return failAt(node, peek());
    js.Catch other = peek();
    return testNodes(node.declaration, other.declaration) &&
        testNodes(node.body, other.body);
  }

  @override
  bool visitTry(js.Try node) {
    if (peek() is! js.Try) return failAt(node, peek());
    js.Try other = peek();
    return testNodes(node.body, other.body) &&
        testNodes(node.catchPart, other.catchPart) &&
        testNodes(node.finallyPart, other.finallyPart);
  }

  @override
  bool visitThrow(js.Throw node) {
    if (peek() is! js.Throw) return failAt(node, peek());
    js.Throw other = peek();
    return testNodes(node.expression, other.expression);
  }

  @override
  bool visitReturn(js.Return node) {
    if (peek() is! js.Return) return failAt(node, peek());
    js.Return other = peek();
    return testNodes(node.value, other.value);
  }

  @override
  bool visitBreak(js.Break node) {
    if (peek() is! js.Break) return failAt(node, peek());
    js.Break other = peek();
    return testLabels(node.targetLabel, other.targetLabel);
  }

  @override
  bool visitContinue(js.Continue node) {
    if (peek() is! js.Continue) return failAt(node, peek());
    js.Continue other = peek();
    return testLabels(node.targetLabel, other.targetLabel);
  }

  @override
  bool visitDo(js.Do node) {
    if (peek() is! js.Do) return failAt(node, peek());
    js.Do other = peek();
    return testNodes(node.condition, other.condition) &&
        testNodes(node.body, other.body);
  }

  @override
  bool visitWhile(js.While node) {
    if (peek() is! js.While) return failAt(node, peek());
    js.While other = peek();
    return testNodes(node.condition, other.condition) &&
        testNodes(node.body, other.body);
  }

  @override
  bool visitForIn(js.ForIn node) {
    if (peek() is! js.ForIn) return failAt(node, peek());
    js.ForIn other = peek();
    return testNodes(node.leftHandSide, other.leftHandSide) &&
        testNodes(node.object, other.object) &&
        testNodes(node.body, other.body);
  }

  @override
  bool visitFor(js.For node) {
    if (peek() is! js.For) return failAt(node, peek());
    js.For other = peek();
    return testNodes(node.init, other.init) &&
        testNodes(node.condition, other.condition) &&
        testNodes(node.update, other.update) &&
        testNodes(node.body, other.body);
  }

  @override
  bool visitIf(js.If node) {
    if (peek() is! js.If) return failAt(node, peek());
    js.If other = peek();
    return testNodes(node.condition, other.condition) &&
        testNodes(node.then, other.then) &&
        testNodes(node.otherwise, other.otherwise);
  }

  @override
  bool visitEmptyStatement(js.EmptyStatement node) {
    if (peek() is! js.EmptyStatement) return failAt(node, peek());
    return true;
  }

  @override
  bool visitExpressionStatement(js.ExpressionStatement node) {
    if (peek() is! js.ExpressionStatement) return failAt(node, peek());
    js.ExpressionStatement other = peek();
    return testNodes(node.expression, other.expression);
  }

  @override
  bool visitBlock(js.Block node) {
    if (peek() is! js.Block) return failAt(node, peek());
    js.Block other = peek();
    return testNodeLists(node.statements, other.statements);
  }
}
