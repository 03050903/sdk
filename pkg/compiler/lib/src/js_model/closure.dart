// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart' as ir;

import '../closure.dart';
import '../common.dart';
import '../common/tasks.dart';
import '../elements/elements.dart';
import '../elements/entities.dart';
import '../elements/entity_utils.dart' as utils;
import '../elements/names.dart' show Name;
import '../kernel/element_map.dart';
import '../world.dart';
import 'elements.dart';
import 'closure_visitors.dart';
import 'locals.dart';
import 'js_strategy.dart' show JsClosedWorld;

/// Closure conversion code using our new Entity model. Closure conversion is
/// necessary because the semantics of closures are slightly different in Dart
/// than JavaScript. Closure conversion is separated out into two phases:
/// generation of a new (temporary) representation to store where variables need
/// to be hoisted/captured up at another level to re-write the closure, and then
/// the code generation phase where we generate elements and/or instructions to
/// represent this new code path.
///
/// For a general explanation of how closure conversion works at a high level,
/// check out:
/// http://siek.blogspot.com/2012/07/essence-of-closure-conversion.html or
/// http://matt.might.net/articles/closure-conversion/.
// TODO(efortuna): Change inheritance hierarchy so that the
// ClosureConversionTask doesn't inherit from ClosureTask because it's just a
// glorified timer.
class KernelClosureConversionTask extends ClosureConversionTask<ir.Node> {
  final KernelToElementMapForBuilding _elementMap;
  final GlobalLocalsMap _globalLocalsMap;

  /// Map of the scoping information that corresponds to a particular entity.
  Map<Entity, ScopeInfo> _scopeMap = <Entity, ScopeInfo>{};
  Map<ir.Node, CapturedScope> _capturedScopesMap = <ir.Node, CapturedScope>{};

  Map<Entity, ClosureRepresentationInfo> _closureRepresentationMap =
      <Entity, ClosureRepresentationInfo>{};

  /// Should only be used at the very beginning to ensure we are looking at the
  /// right kind of elements.
  // TODO(efortuna): Remove this map once we have one kernel backend strategy.
  final JsToFrontendMap _kToJElementMap;

  KernelClosureConversionTask(Measurer measurer, this._elementMap,
      this._kToJElementMap, this._globalLocalsMap)
      : super(measurer);

  /// The combined steps of generating our intermediate representation of
  /// closures that need to be rewritten and generating the element model.
  /// Ultimately these two steps will be split apart with the second step
  /// happening later in compilation just before codegen. These steps are
  /// combined here currently to provide a consistent interface to the rest of
  /// the compiler until we are ready to separate these phases.
  @override
  void convertClosures(Iterable<MemberEntity> processedEntities,
      ClosedWorldRefiner closedWorldRefiner) {
    Map<MemberEntity, ClosureModel> closureModels =
        _computeClosureModels(processedEntities);
    _createClosureEntities(closureModels, closedWorldRefiner);
  }

  // TODO(johnniwinther,efortuna): Compute this during resolution. See
  // documentation on [convertClosures].
  Map<MemberEntity, ClosureModel> _computeClosureModels(
      Iterable<MemberEntity> processedEntities) {
    Map<MemberEntity, ClosureModel> closureModels =
        <MemberEntity, ClosureModel>{};

    processedEntities.forEach((MemberEntity kEntity) {
      MemberEntity entity = _kToJElementMap.toBackendMember(kEntity);
      if (entity.isAbstract) return;
      if (entity.isField && !entity.isInstanceMember) {
        MemberDefinition definition = _elementMap.getMemberDefinition(entity);
        assert(definition.kind == MemberKind.regular,
            failedAt(entity, "Unexpected member definition $definition"));
        ir.Field field = definition.node;
        // Skip top-level/static fields without an initializer.
        if (field.initializer == null) return;
      }
      closureModels[entity] = _buildClosureModel(entity);
    });
    return closureModels;
  }

  void _createClosureEntities(Map<MemberEntity, ClosureModel> closureModels,
      JsClosedWorld closedWorldRefiner) {
    closureModels.forEach((MemberEntity member, ClosureModel model) {
      KernelToLocalsMap localsMap = _globalLocalsMap.getLocalsMap(member);
      if (model.scopeInfo != null) {
        _scopeMap[member] = new JsScopeInfo.from(model.scopeInfo, localsMap);
      }

      model.capturedScopesMap
          .forEach((ir.Node node, KernelCapturedScope scope) {
        if (scope is KernelCapturedLoopScope) {
          _capturedScopesMap[node] =
              new JsCapturedLoopScope.from(scope, localsMap);
        } else {
          _capturedScopesMap[node] = new JsCapturedScope.from(scope, localsMap);
        }
      });

      Map<ir.TreeNode, KernelScopeInfo> closuresToGenerate =
          model.closuresToGenerate;
      for (ir.TreeNode node in closuresToGenerate.keys) {
        _produceSyntheticElements(
            member, node, closuresToGenerate[node], closedWorldRefiner);
      }
    });
  }

  /// Inspect members and mark if those members capture any state that needs to
  /// be marked as free variables.
  ClosureModel _buildClosureModel(MemberEntity entity) {
    ClosureModel model = new ClosureModel();
    MemberDefinition definition = _elementMap.getMemberDefinition(entity);
    switch (definition.kind) {
      case MemberKind.regular:
      case MemberKind.constructor:
        break;
      default:
        failedAt(entity, "Unexpected member definition $definition");
    }
    ir.Node node = definition.node;
    CapturedScopeBuilder translator = new CapturedScopeBuilder(model,
        hasThisLocal: entity.isInstanceMember || entity.isConstructor);
    if (entity.isField) {
      if (node is ir.Field && node.initializer != null) {
        translator.translateLazyInitializer(node);
      }
    } else {
      assert(node is ir.Procedure || node is ir.Constructor);
      translator.translateConstructorOrProcedure(node);
    }
    return model;
  }

  /// Given what variables are captured at each point, construct closure classes
  /// with fields containing the captured variables to replicate the Dart
  /// closure semantics in JS. If this closure captures any variables (meaning
  /// the closure accesses a variable that gets accessed at some point), then
  /// boxForCapturedVariables stores the local context for those variables.
  /// If no variables are captured, this parameter is null.
  void _produceSyntheticElements(
      MemberEntity member,
      ir.TreeNode /* ir.Member | ir.FunctionNode */ node,
      KernelScopeInfo info,
      JsClosedWorld closedWorldRefiner) {
    String name = _computeClosureName(node);
    KernelToLocalsMap localsMap = _globalLocalsMap.getLocalsMap(member);
    KernelClosureClass closureClass = closedWorldRefiner.buildClosureClass(
        name, member.library, info, node.location, localsMap);

    Entity entity;
    if (node is ir.Member) {
      entity = member;
    } else {
      assert(node is ir.FunctionNode);
      entity = localsMap.getLocalFunction(node.parent);
      // We want the original declaration where that function is used to point
      // to the correct closure class.
      _closureRepresentationMap[closureClass.callMethod] = closureClass;
    }
    assert(entity != null);
    _closureRepresentationMap[entity] = closureClass;
  }

  // Returns a non-unique name for the given closure element.
  String _computeClosureName(ir.TreeNode treeNode) {
    var parts = <String>[];
    if (treeNode is ir.Field && treeNode.name.name != "") {
      parts.add(treeNode.name.name);
    } else {
      parts.add('closure');
    }
    ir.TreeNode node = treeNode.parent;
    while (node != null &&
        (node is ir.Constructor ||
            node is ir.Class ||
            node is ir.FunctionNode ||
            node is ir.Procedure)) {
      // TODO(johnniwinther): Simplify computed names.
      if (node is ir.Constructor ||
          node.parent is ir.Constructor ||
          (node is ir.Procedure && node.kind == ir.ProcedureKind.Factory)) {
        FunctionEntity entity;
        if (node.parent is ir.Constructor) {
          entity = _elementMap.getConstructorBody(node);
        } else {
          entity = _elementMap.getMember(node);
        }
        parts.add(utils.reconstructConstructorName(entity));
      } else {
        String surroundingName = '';
        if (node is ir.Class) {
          surroundingName = Elements.operatorNameToIdentifier(node.name);
        } else if (node is ir.Procedure) {
          surroundingName = Elements.operatorNameToIdentifier(node.name.name);
        }
        parts.add(surroundingName);
      }
      // A generative constructors's parent is the class; the class name is
      // already part of the generative constructor's name.
      if (node is ir.Constructor) break;
      node = node.parent;
    }
    return parts.reversed.join('_');
  }

  @override
  ScopeInfo getScopeInfo(Entity entity) {
    // TODO(johnniwinther): Remove this check when constructor bodies a created
    // eagerly with the J-model; a constructor body should have it's own
    // [ClosureRepresentationInfo].
    if (entity is ConstructorBodyEntity) {
      ConstructorBodyEntity constructorBody = entity;
      entity = constructorBody.constructor;
    }

    return _scopeMap[entity] ?? getClosureRepresentationInfo(entity);
  }

  // TODO(efortuna): Eventually capturedScopesMap[node] should always
  // be non-null, and we should just test that with an assert.
  @override
  CapturedScope getCapturedScope(MemberEntity entity) {
    MemberDefinition definition = _elementMap.getMemberDefinition(entity);
    switch (definition.kind) {
      case MemberKind.regular:
      case MemberKind.constructor:
      case MemberKind.constructorBody:
        return _capturedScopesMap[definition.node] ?? const CapturedScope();
      default:
        throw failedAt(entity, "Unexpected member definition $definition");
    }
  }

  @override
  // TODO(efortuna): Eventually capturedScopesMap[node] should always
  // be non-null, and we should just test that with an assert.
  CapturedLoopScope getCapturedLoopScope(ir.Node loopNode) =>
      _capturedScopesMap[loopNode] ?? const CapturedLoopScope();

  @override
  // TODO(efortuna): Eventually closureRepresentationMap[node] should always be
  // non-null, and we should just test that with an assert.
  ClosureRepresentationInfo getClosureRepresentationInfo(Entity entity) {
    return _closureRepresentationMap[entity] ??
        const ClosureRepresentationInfo();
  }
}

class KernelScopeInfo {
  final Set<ir.VariableDeclaration> localsUsedInTryOrSync;
  final bool hasThisLocal;
  final Set<ir.VariableDeclaration> boxedVariables;

  /// The set of variables that were defined in another scope, but are used in
  /// this scope.
  Set<ir.VariableDeclaration> freeVariables = new Set<ir.VariableDeclaration>();

  KernelScopeInfo(this.hasThisLocal)
      : localsUsedInTryOrSync = new Set<ir.VariableDeclaration>(),
        boxedVariables = new Set<ir.VariableDeclaration>();

  KernelScopeInfo.from(this.hasThisLocal, KernelScopeInfo info)
      : localsUsedInTryOrSync = info.localsUsedInTryOrSync,
        boxedVariables = info.boxedVariables;

  KernelScopeInfo.withBoxedVariables(this.boxedVariables,
      this.localsUsedInTryOrSync, this.freeVariables, this.hasThisLocal);

  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write('this=$hasThisLocal,');
    sb.write('localsUsedInTryOrSync={${localsUsedInTryOrSync.join(', ')}}');
    return sb.toString();
  }
}

class JsScopeInfo extends ScopeInfo {
  final Set<Local> localsUsedInTryOrSync;
  final Local thisLocal;
  final Set<Local> boxedVariables;

  /// The set of variables that were defined in another scope, but are used in
  /// this scope.
  final Set<Local> freeVariables;

  JsScopeInfo(this.thisLocal, this.localsUsedInTryOrSync, this.boxedVariables,
      this.freeVariables);

  JsScopeInfo.from(KernelScopeInfo info, KernelToLocalsMap localsMap)
      : this.thisLocal =
            info.hasThisLocal ? new ThisLocal(localsMap.currentMember) : null,
        this.localsUsedInTryOrSync =
            info.localsUsedInTryOrSync.map(localsMap.getLocalVariable).toSet(),
        this.boxedVariables =
            info.boxedVariables.map(localsMap.getLocalVariable).toSet(),
        this.freeVariables =
            info.freeVariables.map(localsMap.getLocalVariable).toSet();

  void forEachBoxedVariable(f(Local local, FieldEntity field)) {
    boxedVariables.forEach((Local l) {
      // TODO(efortuna): add FieldEntities as created.
      f(l, null);
    });
  }

  bool localIsUsedInTryOrSync(Local variable) =>
      localsUsedInTryOrSync.contains(variable);

  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write('this=$thisLocal,');
    sb.write('localsUsedInTryOrSync={${localsUsedInTryOrSync.join(', ')}}');
    return sb.toString();
  }

  bool isBoxed(Local variable) => boxedVariables.contains(variable);
}

class KernelCapturedScope extends KernelScopeInfo {
  final ir.TreeNode context;

  KernelCapturedScope(
      Set<ir.VariableDeclaration> boxedVariables,
      this.context,
      Set<ir.VariableDeclaration> localsUsedInTryOrSync,
      Set<ir.VariableDeclaration> freeVariables,
      bool hasThisLocal)
      : super.withBoxedVariables(
            boxedVariables, localsUsedInTryOrSync, freeVariables, hasThisLocal);

  bool get requiresContextBox => boxedVariables.isNotEmpty;
}

class JsCapturedScope extends JsScopeInfo implements CapturedScope {
  final Local context;

  JsCapturedScope.from(
      KernelCapturedScope capturedScope, KernelToLocalsMap localsMap)
      : this.context = localsMap.getLocalVariable(capturedScope.context),
        super.from(capturedScope, localsMap);

  bool get requiresContextBox => boxedVariables.isNotEmpty;
}

class KernelCapturedLoopScope extends KernelCapturedScope {
  final List<ir.VariableDeclaration> boxedLoopVariables;

  KernelCapturedLoopScope(
      Set<ir.VariableDeclaration> boxedVariables,
      this.boxedLoopVariables,
      ir.TreeNode context,
      Set<ir.VariableDeclaration> localsUsedInTryOrSync,
      Set<ir.VariableDeclaration> freeVariables,
      bool hasThisLocal)
      : super(boxedVariables, context, localsUsedInTryOrSync, freeVariables,
            hasThisLocal);

  bool get hasBoxedLoopVariables => boxedLoopVariables.isNotEmpty;
}

class JsCapturedLoopScope extends JsCapturedScope implements CapturedLoopScope {
  final List<Local> boxedLoopVariables;

  JsCapturedLoopScope.from(
      KernelCapturedLoopScope capturedScope, KernelToLocalsMap localsMap)
      : this.boxedLoopVariables = capturedScope.boxedLoopVariables
            .map(localsMap.getLocalVariable)
            .toList(),
        super.from(capturedScope, localsMap);

  bool get hasBoxedLoopVariables => boxedLoopVariables.isNotEmpty;
}

// TODO(johnniwinther): Add unittest for the computed [ClosureClass].
class KernelClosureClass extends JsScopeInfo
    implements ClosureRepresentationInfo, JClass {
  final ir.Location location;

  final String name;
  final JLibrary library;

  /// Index into the classData, classList and classEnvironment lists where this
  /// entity is stored in [JsToFrontendMapImpl].
  final int classIndex;

  final Map<Local, JField> localToFieldMap = new Map<Local, JField>();

  KernelClosureClass.fromScopeInfo(this.name, this.classIndex, this.library,
      KernelScopeInfo info, this.location, KernelToLocalsMap localsMap)
      : super.from(info, localsMap);

  // TODO(efortuna): Implement.
  Local get closureEntity => null;

  ClassEntity get closureClassEntity => this;

  // TODO(efortuna): Implement.
  FunctionEntity get callMethod => null;

  List<Local> get createdFieldEntities => localToFieldMap.keys.toList();

  // TODO(efortuna): Implement.
  FieldEntity get thisFieldEntity => null;

  void forEachCapturedVariable(f(Local from, JField to)) {
    localToFieldMap.forEach(f);
  }

  // TODO(efortuna): Implement.
  @override
  void forEachBoxedVariable(f(Local local, JField field)) {}

  // TODO(efortuna): Implement.
  void forEachFreeVariable(f(Local variable, JField field)) {}

  // TODO(efortuna): Implement.
  bool isVariableBoxed(Local variable) => false;

  bool get isClosure => true;

  bool get isAbstract => false;

  String toString() => '${jsElementPrefix}class($name)';
}

class ClosureField extends JField {
  ClosureField(String name, int memberIndex, KernelClosureClass containingClass,
      bool isConst, bool isAssignable)
      : super(memberIndex, containingClass.library, containingClass,
            new Name(name, containingClass.library),
            isAssignable: isAssignable, isConst: isConst);
}

class ClosureClassDefinition implements ClassDefinition {
  final ClassEntity cls;
  final ir.Location location;

  ClosureClassDefinition(this.cls, this.location);

  ClassKind get kind => ClassKind.closure;

  ir.Node get node =>
      throw new UnsupportedError('ClosureClassDefinition.node for $cls');

  String toString() =>
      'ClosureClassDefinition(kind:$kind,cls:$cls,location:$location)';
}

class ClosureMemberDefinition implements MemberDefinition {
  final MemberEntity member;
  final ir.Location location;
  final MemberKind kind;
  final ir.Node node;

  ClosureMemberDefinition(this.member, this.location, this.kind, this.node);

  String toString() =>
      'ClosureMemberDefinition(kind:$kind,member:$member,location:$location)';
}

/// Collection of closure data collected for a single member.
class ClosureModel {
  /// Collection [ScopeInfo] data for the member, if any.
  // TODO(johnniwinther): [scopeInfo] seem to be missing only for fields
  // without initializers; we shouldn't even create a [ClosureModel] in these
  // cases.
  KernelScopeInfo scopeInfo;

  /// Collected [CapturedScope] data for nodes.
  Map<ir.Node, KernelCapturedScope> capturedScopesMap =
      <ir.Node, KernelCapturedScope>{};

  /// Collected [ScopeInfo] data for nodes.
  Map<ir.TreeNode, KernelScopeInfo> closuresToGenerate =
      <ir.TreeNode, KernelScopeInfo>{};
}
