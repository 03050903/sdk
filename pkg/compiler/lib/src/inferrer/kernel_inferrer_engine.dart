// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart' as ir;

import '../../compiler_new.dart';
import '../closure.dart';
import '../common.dart';
import '../common_elements.dart';
import '../common/names.dart';
import '../compiler.dart';
import '../constants/values.dart';
import '../elements/entities.dart';
import '../elements/types.dart';
import '../js_backend/inferred_data.dart';
import '../js_backend/no_such_method_registry.dart';
import '../js_emitter/sorter.dart';
import '../js_model/locals.dart';
import '../kernel/element_map.dart';
import '../options.dart';
import '../types/abstract_value_domain.dart';
import '../types/types.dart';
import '../world.dart';
import 'builder_kernel.dart';
import 'inferrer_engine.dart';
import 'type_graph_inferrer.dart';
import 'type_graph_nodes.dart';
import 'type_system.dart';

class KernelTypeGraphInferrer extends TypeGraphInferrer {
  final Compiler _compiler;
  final KernelToElementMapForBuilding _elementMap;
  final GlobalLocalsMap _globalLocalsMap;
  final ClosureDataLookup _closureDataLookup;
  final InferredDataBuilder _inferredDataBuilder;

  KernelTypeGraphInferrer(
      this._compiler,
      this._elementMap,
      this._globalLocalsMap,
      this._closureDataLookup,
      JClosedWorld closedWorld,
      this._inferredDataBuilder,
      {bool disableTypeInference: false})
      : super(closedWorld, disableTypeInference: disableTypeInference);

  @override
  InferrerEngine createInferrerEngineFor(FunctionEntity main) {
    return new KernelInferrerEngine(
        _compiler.options,
        _compiler.progress,
        _compiler.reporter,
        _compiler.outputProvider,
        _elementMap,
        _globalLocalsMap,
        _closureDataLookup,
        closedWorld,
        _compiler.backend.noSuchMethodRegistry,
        main,
        _compiler.backendStrategy.sorter,
        _inferredDataBuilder);
  }
}

class KernelInferrerEngine extends InferrerEngineImpl {
  final KernelToElementMapForBuilding _elementMap;
  final GlobalLocalsMap _globalLocalsMap;
  final ClosureDataLookup _closureDataLookup;

  KernelInferrerEngine(
      CompilerOptions options,
      Progress progress,
      DiagnosticReporter reporter,
      CompilerOutput compilerOutput,
      this._elementMap,
      this._globalLocalsMap,
      this._closureDataLookup,
      JClosedWorld closedWorld,
      NoSuchMethodRegistry noSuchMethodRegistry,
      FunctionEntity mainElement,
      Sorter sorter,
      InferredDataBuilder inferredDataBuilder)
      : super(
            options,
            progress,
            reporter,
            compilerOutput,
            closedWorld,
            noSuchMethodRegistry,
            mainElement,
            sorter,
            inferredDataBuilder,
            new KernelTypeSystemStrategy(
                _elementMap, _globalLocalsMap, _closureDataLookup));

  ElementEnvironment get _elementEnvironment => _elementMap.elementEnvironment;

  @override
  ConstantValue getFieldConstant(FieldEntity field) {
    return _elementMap.getFieldConstantValue(field);
  }

  @override
  bool isFieldInitializerPotentiallyNull(
      FieldEntity field, ir.Node initializer) {
    // TODO(13429): We could do better here by using the
    // constant handler to figure out if it's a lazy field or not.
    // TODO(johnniwinther): Implement the ad-hoc check in ast inferrer? This
    // mimicks that ast inferrer which return `true` for [ast.Send] and
    // non-const [ast.NewExpression].
    if (initializer is ir.MethodInvocation ||
        initializer is ir.PropertyGet ||
        initializer is ir.PropertySet ||
        initializer is ir.StaticInvocation ||
        initializer is ir.StaticGet ||
        initializer is ir.StaticSet ||
        initializer is ir.Let ||
        initializer is ir.ConstructorInvocation && !initializer.isConst) {
      return true;
    }
    return false;
  }

  @override
  TypeInformation computeMemberTypeInformation(
      MemberEntity member, ir.Node body) {
    KernelTypeGraphBuilder visitor = new KernelTypeGraphBuilder(
        options,
        closedWorld,
        _closureDataLookup,
        this,
        member,
        body,
        _elementMap,
        _globalLocalsMap.getLocalsMap(member));
    return visitor.run();
  }

  @override
  FunctionEntity lookupCallMethod(ClassEntity cls) {
    FunctionEntity function =
        _elementEnvironment.lookupClassMember(cls, Identifiers.call);
    if (function == null || function.isAbstract) {
      function =
          _elementEnvironment.lookupClassMember(cls, Identifiers.noSuchMethod_);
    }
    return function;
  }

  @override
  ir.Node computeMemberBody(MemberEntity member) {
    MemberDefinition definition = _elementMap.getMemberDefinition(member);
    switch (definition.kind) {
      case MemberKind.regular:
        ir.Member node = definition.node;
        if (node is ir.Field) {
          return getFieldInitializer(_elementMap, member);
        } else if (node is ir.Procedure) {
          return node.function;
        }
        break;
      case MemberKind.constructor:
        return definition.node;
      case MemberKind.constructorBody:
        ir.Member node = definition.node;
        if (node is ir.Constructor) {
          return node.function;
        } else if (node is ir.Procedure) {
          return node.function;
        }
        break;
      case MemberKind.closureCall:
        ir.TreeNode node = definition.node;
        if (node is ir.FunctionDeclaration) {
          return node.function;
        } else if (node is ir.FunctionExpression) {
          return node.function;
        }
        break;
      case MemberKind.closureField:
      case MemberKind.signature:
      case MemberKind.generatorBody:
        break;
    }
    failedAt(member, 'Unexpected member definition: $definition.');
    return null;
  }

  @override
  int computeMemberSize(MemberEntity member) {
    // TODO(johnniwinther): Find an ordering that can be shared between the
    // front ends.
    return 0;
  }

  @override
  GlobalTypeInferenceElementData createElementData() {
    return new KernelGlobalTypeInferenceElementData();
  }

  @override
  bool hasCallType(ClassEntity cls) {
    return _elementMap.types
            .getCallType(_elementMap.elementEnvironment.getThisType(cls)) !=
        null;
  }
}

class KernelTypeSystemStrategy implements TypeSystemStrategy {
  KernelToElementMapForBuilding _elementMap;
  GlobalLocalsMap _globalLocalsMap;
  ClosureDataLookup _closureDataLookup;

  KernelTypeSystemStrategy(
      this._elementMap, this._globalLocalsMap, this._closureDataLookup);

  ElementEnvironment get _elementEnvironment => _elementMap.elementEnvironment;

  @override
  bool checkClassEntity(ClassEntity cls) => true;

  @override
  bool checkMapNode(ir.Node node) => true;

  @override
  bool checkListNode(ir.Node node) => true;

  @override
  bool checkLoopPhiNode(ir.Node node) => true;

  @override
  bool checkPhiNode(ir.Node node) => true;

  @override
  void forEachParameter(FunctionEntity function, void f(Local parameter)) {
    forEachOrderedParameter(_globalLocalsMap, _elementMap, function, f);
  }

  @override
  ParameterTypeInformation createParameterTypeInformation(
      AbstractValueDomain abstractValueDomain,
      covariant JLocal parameter,
      TypeSystem types) {
    MemberEntity context = parameter.memberContext;
    KernelToLocalsMap localsMap = _globalLocalsMap.getLocalsMap(context);
    ir.FunctionNode functionNode =
        localsMap.getFunctionNodeForParameter(parameter);
    DartType type = localsMap.getLocalType(_elementMap, parameter);
    MemberEntity member;
    bool isClosure = false;
    if (functionNode.parent is ir.Member) {
      member = _elementMap.getMember(functionNode.parent);
    } else if (functionNode.parent is ir.FunctionExpression ||
        functionNode.parent is ir.FunctionDeclaration) {
      ClosureRepresentationInfo info =
          _closureDataLookup.getClosureInfo(functionNode.parent);
      member = info.callMethod;
      isClosure = true;
    }
    MemberTypeInformation memberTypeInformation =
        types.getInferredTypeOfMember(member);
    if (isClosure) {
      return new ParameterTypeInformation.localFunction(
          abstractValueDomain, memberTypeInformation, parameter, type, member);
    } else if (member.isInstanceMember) {
      return new ParameterTypeInformation.instanceMember(
          abstractValueDomain,
          memberTypeInformation,
          parameter,
          type,
          member,
          new ParameterAssignments());
    } else {
      return new ParameterTypeInformation.static(
          abstractValueDomain, memberTypeInformation, parameter, type, member);
    }
  }

  @override
  MemberTypeInformation createMemberTypeInformation(
      AbstractValueDomain abstractValueDomain, MemberEntity member) {
    if (member.isField) {
      FieldEntity field = member;
      DartType type = _elementEnvironment.getFieldType(field);
      return new FieldTypeInformation(abstractValueDomain, field, type);
    } else if (member.isGetter) {
      FunctionEntity getter = member;
      DartType type = _elementEnvironment.getFunctionType(getter);
      return new GetterTypeInformation(abstractValueDomain, getter, type);
    } else if (member.isSetter) {
      FunctionEntity setter = member;
      return new SetterTypeInformation(abstractValueDomain, setter);
    } else if (member.isFunction) {
      FunctionEntity method = member;
      DartType type = _elementEnvironment.getFunctionType(method);
      return new MethodTypeInformation(abstractValueDomain, method, type);
    } else {
      ConstructorEntity constructor = member;
      if (constructor.isFactoryConstructor) {
        DartType type = _elementEnvironment.getFunctionType(constructor);
        return new FactoryConstructorTypeInformation(
            abstractValueDomain, constructor, type);
      } else {
        return new GenerativeConstructorTypeInformation(
            abstractValueDomain, constructor);
      }
    }
  }
}

class KernelGlobalTypeInferenceElementData
    extends GlobalTypeInferenceElementData {
  // TODO(johnniwinther): Rename this together with [typeOfSend].
  Map<ir.Node, AbstractValue> _sendMap;

  Map<ir.ForInStatement, AbstractValue> _iteratorMap;
  Map<ir.ForInStatement, AbstractValue> _currentMap;
  Map<ir.ForInStatement, AbstractValue> _moveNextMap;

  @override
  AbstractValue typeOfSend(ir.Node node) {
    if (_sendMap == null) return null;
    return _sendMap[node];
  }

  @override
  void setCurrentTypeMask(
      covariant ir.ForInStatement node, AbstractValue mask) {
    _currentMap ??= <ir.ForInStatement, AbstractValue>{};
    _currentMap[node] = mask;
  }

  @override
  void setMoveNextTypeMask(
      covariant ir.ForInStatement node, AbstractValue mask) {
    _moveNextMap ??= <ir.ForInStatement, AbstractValue>{};
    _moveNextMap[node] = mask;
  }

  @override
  void setIteratorTypeMask(
      covariant ir.ForInStatement node, AbstractValue mask) {
    _iteratorMap ??= <ir.ForInStatement, AbstractValue>{};
    _iteratorMap[node] = mask;
  }

  @override
  AbstractValue typeOfIteratorCurrent(covariant ir.ForInStatement node) {
    if (_currentMap == null) return null;
    return _currentMap[node];
  }

  @override
  AbstractValue typeOfIteratorMoveNext(covariant ir.ForInStatement node) {
    if (_moveNextMap == null) return null;
    return _moveNextMap[node];
  }

  @override
  AbstractValue typeOfIterator(covariant ir.ForInStatement node) {
    if (_iteratorMap == null) return null;
    return _iteratorMap[node];
  }

  @override
  void setTypeMask(ir.Node node, AbstractValue mask) {
    _sendMap ??= <ir.Node, AbstractValue>{};
    _sendMap[node] = mask;
  }

  @override
  AbstractValue typeOfGetter(ir.Node node) {
    if (_sendMap == null) return null;
    return _sendMap[node];
  }
}

/// Returns the initializer for [field].
///
/// If [field] is an instance field with a null literal initializer `null` is
/// returned, otherwise the initializer of the [ir.Field] is returned.
ir.Node getFieldInitializer(
    KernelToElementMapForBuilding elementMap, FieldEntity field) {
  MemberDefinition definition = elementMap.getMemberDefinition(field);
  ir.Field node = definition.node;
  if (node.isInstanceMember &&
      !node.isFinal &&
      node.initializer is ir.NullLiteral) {
    return null;
  }
  return node.initializer;
}
