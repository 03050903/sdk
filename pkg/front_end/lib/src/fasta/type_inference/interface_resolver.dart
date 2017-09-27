// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

import 'package:front_end/src/fasta/kernel/kernel_shadow_ast.dart';
import 'package:front_end/src/fasta/problems.dart';
import 'package:front_end/src/fasta/type_inference/type_inference_engine.dart';
import 'package:front_end/src/fasta/type_inference/type_inferrer.dart';
import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/type_algebra.dart';
import 'package:kernel/type_environment.dart';

/// Type of a closure which applies a covariance annotation to a class member.
///
/// This is necessary since we need to determine which covariance annotations
/// need to be added before creating a forwarding stub, but the covariance
/// annotations themselves need to be applied to the forwarding stub.
typedef void _CovarianceFix(FunctionNode);

/// A [ForwardingNode] represents a method, getter, or setter within a class's
/// interface that is either implemented in the class directly or inherited from
/// a superclass.
///
/// This class allows us to defer the determination of exactly which member is
/// inherited, as well as the propagation of covariance annotations, and
/// the creation of forwarding stubs, until type inference.
class ForwardingNode extends Procedure {
  /// The [InterfaceResolver] that created this [ForwardingNode].
  final InterfaceResolver _interfaceResolver;

  /// A list containing the directly implemented and directly inherited
  /// procedures of the class in question.
  ///
  /// Note that many [ForwardingNode]s share the same [_candidates] list;
  /// consult [_start] and [_end] to see which entries in this list are relevant
  /// to this [ForwardingNode].
  final List<Procedure> _candidates;

  /// Indicates whether this forwarding node is for a setter.
  final bool _setter;

  /// Index of the first entry in [_candidates] relevant to this
  /// [ForwardingNode].
  final int _start;

  /// Index just beyond the last entry in [_candidates] relevant to this
  /// [ForwardingNode].
  final int _end;

  /// The member this node resolves to (if it has been computed); otherwise
  /// `null`.
  Member _resolution;

  ForwardingNode(
      this._interfaceResolver,
      Class class_,
      Name name,
      ProcedureKind kind,
      this._candidates,
      this._setter,
      this._start,
      this._end)
      : super(name, kind, null) {
    parent = class_;
  }

  /// Returns the inherited member, or the forwarding stub, which this node
  /// resolves to.
  Member resolve() => _resolution ??= _resolve();

  /// Determines which covariance fixes need to be applied to the given
  /// [interfaceMember].
  ///
  /// [substitution] indicates the necessary substitutions to convert types
  /// named in [interfaceMember] to types in the target class.
  ///
  /// The fixes are not applied immediately (since [interfaceMember] might be
  /// a member of another class, and a forwarding stub may need to be
  /// generated).
  void _computeCovarianceFixes(Substitution substitution,
      Procedure interfaceMember, List<_CovarianceFix> fixes) {
    var class_ = enclosingClass;
    var interfaceFunction = interfaceMember.function;
    var interfacePositionalParameters = interfaceFunction.positionalParameters;
    var interfaceNamedParameters = interfaceFunction.namedParameters;
    var interfaceTypeParameters = interfaceFunction.typeParameters;
    if (class_.typeParameters.isNotEmpty) {
      IncludesTypeParametersCovariantly needsCheckVisitor =
          ShadowClass.getClassInferenceInfo(class_).needsCheckVisitor ??=
              new IncludesTypeParametersCovariantly(class_.typeParameters);
      bool needsCheck(DartType type) =>
          substitution.substituteType(type).accept(needsCheckVisitor);
      for (int i = 0; i < interfacePositionalParameters.length; i++) {
        var parameter = interfacePositionalParameters[i];
        var isCovariant = needsCheck(parameter.type);
        if (isCovariant != parameter.isGenericCovariantInterface) {
          fixes.add((FunctionNode function) => function.positionalParameters[i]
              .isGenericCovariantInterface = isCovariant);
        }
        if (isCovariant != parameter.isGenericCovariantImpl) {
          fixes.add((FunctionNode function) => function
              .positionalParameters[i].isGenericCovariantImpl = isCovariant);
        }
      }
      for (int i = 0; i < interfaceNamedParameters.length; i++) {
        var parameter = interfaceNamedParameters[i];
        var isCovariant = needsCheck(parameter.type);
        if (isCovariant != parameter.isGenericCovariantInterface) {
          fixes.add((FunctionNode function) => function
              .namedParameters[i].isGenericCovariantInterface = isCovariant);
        }
        if (isCovariant != parameter.isGenericCovariantImpl) {
          fixes.add((FunctionNode function) =>
              function.namedParameters[i].isGenericCovariantImpl = isCovariant);
        }
      }
      for (int i = 0; i < interfaceTypeParameters.length; i++) {
        var typeParameter = interfaceTypeParameters[i];
        var isCovariant = needsCheck(typeParameter.bound);
        if (isCovariant != typeParameter.isGenericCovariantInterface) {
          fixes.add((FunctionNode function) => function
              .typeParameters[i].isGenericCovariantInterface = isCovariant);
        }
        if (isCovariant != typeParameter.isGenericCovariantImpl) {
          fixes.add((FunctionNode function) =>
              function.typeParameters[i].isGenericCovariantImpl = isCovariant);
        }
      }
    }
    for (int i = _start; i < _end; i++) {
      var otherMember = _candidates[i];
      if (identical(otherMember, interfaceMember)) continue;
      var otherFunction = otherMember.function;
      var otherPositionalParameters = otherFunction.positionalParameters;
      for (int j = 0;
          j < interfacePositionalParameters.length &&
              j < otherPositionalParameters.length;
          j++) {
        var parameter = interfacePositionalParameters[j];
        var otherParameter = otherPositionalParameters[j];
        if (otherParameter.isGenericCovariantImpl &&
            !parameter.isGenericCovariantImpl) {
          fixes.add((FunctionNode function) =>
              function.positionalParameters[j].isGenericCovariantImpl = true);
        }
        if (otherParameter.isCovariant && !parameter.isCovariant) {
          fixes.add((FunctionNode function) =>
              function.positionalParameters[j].isCovariant = true);
        }
      }
      for (int j = 0; j < interfaceNamedParameters.length; j++) {
        var parameter = interfaceNamedParameters[j];
        var otherParameter = getNamedFormal(otherFunction, parameter.name);
        if (otherParameter != null) {
          if (otherParameter.isGenericCovariantImpl &&
              !parameter.isGenericCovariantImpl) {
            fixes.add((FunctionNode function) =>
                function.namedParameters[j].isGenericCovariantImpl = true);
          }
          if (otherParameter.isCovariant && !parameter.isCovariant) {
            fixes.add((FunctionNode function) =>
                function.namedParameters[j].isCovariant = true);
          }
        }
      }
      var otherTypeParameters = otherFunction.typeParameters;
      for (int j = 0;
          j < interfaceTypeParameters.length && j < otherTypeParameters.length;
          j++) {
        var typeParameter = interfaceTypeParameters[j];
        var otherTypeParameter = otherTypeParameters[j];
        if (otherTypeParameter.isGenericCovariantImpl &&
            !typeParameter.isGenericCovariantImpl) {
          fixes.add((FunctionNode function) =>
              function.typeParameters[j].isGenericCovariantImpl = true);
        }
      }
    }
  }

  /// Creates a forwarding stub based on the given [target].
  ForwardingStub _createForwardingStub(
      Substitution substitution, Procedure target) {
    VariableDeclaration copyParameter(VariableDeclaration parameter) {
      return new VariableDeclaration(parameter.name,
          type: substitution.substituteType(parameter.type));
    }

    TypeParameter copyTypeParameter(TypeParameter typeParameter) {
      return new TypeParameter(
          typeParameter.name, substitution.substituteType(typeParameter.bound));
    }

    var positionalParameters = <VariableDeclaration>[];
    var positionalArguments = <Expression>[];
    for (var parameter in target.function.positionalParameters) {
      var copiedParameter = copyParameter(parameter);
      positionalParameters.add(copiedParameter);
      positionalArguments.add(new VariableGet(copiedParameter));
    }
    var namedParameters = <VariableDeclaration>[];
    var namedArguments = <NamedExpression>[];
    for (var parameter in target.function.namedParameters) {
      var copiedParameter = copyParameter(parameter);
      namedParameters.add(copiedParameter);
      namedArguments.add(new NamedExpression(
          parameter.name, new VariableGet(copiedParameter)));
    }
    var typeParameters = <TypeParameter>[];
    var typeArguments = <DartType>[];
    for (var typeParameter in target.function.typeParameters) {
      var copiedTypeParameter = copyTypeParameter(typeParameter);
      typeParameters.add(copiedTypeParameter);
      typeArguments.add(new TypeParameterType(copiedTypeParameter));
    }
    var arguments = new Arguments(positionalArguments,
        types: typeArguments, named: namedArguments);
    Expression superCall;
    switch (target.kind) {
      case ProcedureKind.Method:
        superCall = new SuperMethodInvocation(name, arguments, target);
        break;
      case ProcedureKind.Getter:
        superCall = new SuperPropertyGet(
            name, target is SyntheticAccessor ? target._field : target);
        break;
      case ProcedureKind.Setter:
        superCall = new SuperPropertySet(name, positionalArguments[0],
            target is SyntheticAccessor ? target._field : target);
        break;
      default:
        unhandled('${target.kind}', '_createForwardingStub', -1, null);
        break;
    }
    var function = new FunctionNode(new ReturnStatement(superCall),
        positionalParameters: positionalParameters,
        namedParameters: namedParameters,
        typeParameters: typeParameters,
        requiredParameterCount: target.function.requiredParameterCount,
        returnType: substitution.substituteType(target.function.returnType));
    return new ForwardingStub(name, kind, function);
  }

  /// Determines which inherited member this node resolves to.
  Member _resolve() {
    var inheritedMember = _candidates[_start];
    var inheritedMemberSubstitution = Substitution.empty;
    bool isDeclaredInThisClass =
        identical(inheritedMember.enclosingClass, enclosingClass);
    if (!isDeclaredInThisClass) {
      // If there are multiple inheritance candidates, the inherited member is
      // the member whose type is a subtype of all the others.  We can find it
      // by two passes over the list of members.  For the first pass, we step
      // through the candidates, updating inheritedMember each time we find a
      // member whose type is a subtype of the previous inheritedMember.  As we
      // do this, we also work out the necessary substitution for matching up
      // type parameters between this class and the corresponding superclass.
      //
      // Since the subtyping relation is reflexive, we will favor the most
      // recently visited candidate in the case where the types are the same.
      // We want to favor earlier candidates, so we visit the candidate list
      // backwards.
      inheritedMember = _candidates[_end - 1];
      inheritedMemberSubstitution = _substitutionFor(inheritedMember);
      var inheritedMemberType = inheritedMemberSubstitution.substituteType(
          _setter ? inheritedMember.setterType : inheritedMember.getterType);
      for (int i = _end - 2; i >= _start; i--) {
        var candidate = _candidates[i];
        var substitution = _substitutionFor(candidate);
        bool isBetter;
        DartType type;
        if (_setter) {
          type = substitution.substituteType(candidate.setterType);
          // Setters are contravariant in their setter type, so we have to
          // reverse the check.
          isBetter = _interfaceResolver._typeEnvironment
              .isSubtypeOf(inheritedMemberType, type);
        } else {
          type = substitution.substituteType(candidate.getterType);
          isBetter = _interfaceResolver._typeEnvironment
              .isSubtypeOf(type, inheritedMemberType);
        }
        if (isBetter) {
          inheritedMember = candidate;
          inheritedMemberSubstitution = substitution;
          inheritedMemberType = type;
        }
      }
      // For the second pass, we verify that inheritedMember is a subtype of all
      // the other potentially inherited members.
      // TODO(paulberry): implement this.
    }

    // Now decide whether we need a forwarding stub or not, and propagate
    // covariance.
    var covarianceFixes = <_CovarianceFix>[];
    _computeCovarianceFixes(
        inheritedMemberSubstitution, inheritedMember, covarianceFixes);
    if (!isDeclaredInThisClass &&
        (!identical(inheritedMember, _candidates[_start]) ||
            covarianceFixes.isNotEmpty)) {
      var stub =
          _createForwardingStub(inheritedMemberSubstitution, inheritedMember);
      var function = stub.function;
      for (var fix in covarianceFixes) {
        fix(function);
      }
      return stub;
    } else if (inheritedMember is SyntheticAccessor) {
      // TODO(paulberry): propagate covariance fixes to the field.
      return inheritedMember._field;
    } else {
      var function = inheritedMember.function;
      for (var fix in covarianceFixes) {
        fix(function);
      }
      return inheritedMember;
    }
  }

  /// Determines the appropriate substitution to translate type parameters
  /// mentioned in the given [candidate] to type parameters on the parent class.
  Substitution _substitutionFor(Procedure candidate) {
    return Substitution.fromInterfaceType(
        _interfaceResolver._typeEnvironment.hierarchy.getTypeAsInstanceOf(
            enclosingClass.thisType, candidate.enclosingClass));
  }

  /// Public method allowing tests to access [_createForwardingStub].
  ///
  /// This method is static so that it can be easily eliminated by tree shaking
  /// when not needed.
  static ForwardingStub createForwardingStubForTesting(
      ForwardingNode node, Substitution substitution, Procedure target) {
    return node._createForwardingStub(substitution, target);
  }

  /// For testing: get the list of candidates relevant to a given node.
  static List<Procedure> getCandidates(ForwardingNode node) {
    return node._candidates.sublist(node._start, node._end);
  }
}

/// A forwarding stub created by the [InterfaceResolver].
///
/// This needs to be a derived class from [Procedure] so that we can tell
/// whether a given member is a forwarding stub using an "is" check.
class ForwardingStub extends Procedure {
  ForwardingStub(Name name, ProcedureKind kind, FunctionNode function)
      : super(name, kind, function);
}

/// An [InterfaceResolver] keeps track of the information necessary to resolve
/// method calls, gets, and sets within a chunk of code being compiled, to
/// infer covariance annotations, and to create forwarwding stubs when necessary
/// to meet covariance requirements.
class InterfaceResolver {
  final TypeEnvironment _typeEnvironment;

  InterfaceResolver(this._typeEnvironment);

  /// Populates [forwardingNodes] with a list of the implemented and inherited
  /// members of the given [class_]'s interface.
  ///
  /// Each member of the class's interface is represented by a [ForwardingNode]
  /// object.
  ///
  /// If [setters] is `true`, the list will be populated by setters; otherwise
  /// it will be populated by getters and methods.
  void createForwardingNodes(
      Class class_, List<ForwardingNode> forwardingNodes, bool setters) {
    // First create a list of candidates for inheritance based on the members
    // declared directly in the class.
    List<Procedure> candidates = _typeEnvironment.hierarchy
        .getDeclaredMembers(class_, setters: setters)
        .map((member) => makeCandidate(member, setters))
        .toList();
    // Merge in candidates from superclasses.
    if (class_.superclass != null) {
      candidates = _mergeCandidates(candidates, class_.superclass, setters);
    }
    for (var supertype in class_.implementedTypes) {
      candidates = _mergeCandidates(candidates, supertype.classNode, setters);
    }
    // Now create a forwarding node for each unique name.
    forwardingNodes.length = candidates.length;
    int storeIndex = 0;
    int i = 0;
    while (i < candidates.length) {
      var name = candidates[i].name;
      int j = i + 1;
      while (j < candidates.length && candidates[j].name == name) {
        j++;
      }
      forwardingNodes[storeIndex++] = new ForwardingNode(
          this, class_, name, candidates[i].kind, candidates, setters, i, j);
      i = j;
    }
    forwardingNodes.length = storeIndex;
  }

  /// Retrieves a list of the interface members of the given [class_].
  ///
  /// If [setters] is true, setters are retrieved; otherwise getters and methods
  /// are retrieved.
  List<Member> _getInterfaceMembers(Class class_, bool setters) {
    // TODO(paulberry): if class_ is being compiled from source, retrieve its
    // forwarding nodes.
    return _typeEnvironment.hierarchy
        .getInterfaceMembers(class_, setters: setters);
  }

  /// Merges together the list of interface inheritance candidates in
  /// [candidates] with interface inheritance candidates from superclass
  /// [class_].
  ///
  /// Any candidates from [class_] are converted into interface inheritance
  /// candidates using [_makeCandidate].
  List<Procedure> _mergeCandidates(
      List<Procedure> candidates, Class class_, bool setters) {
    List<Member> members = _getInterfaceMembers(class_, setters);
    if (candidates.isEmpty) {
      return members.map((member) => makeCandidate(member, setters)).toList();
    }
    if (members.isEmpty) return candidates;
    List<Procedure> result = <Procedure>[]..length =
        candidates.length + members.length;
    int storeIndex = 0;
    int i = 0, j = 0;
    while (i < candidates.length && j < members.length) {
      Procedure candidate = candidates[i];
      Member member = members[j];
      int compare = ClassHierarchy.compareMembers(candidate, member);
      if (compare <= 0) {
        result[storeIndex++] = candidate;
        ++i;
        // If the same member occurs in both lists, skip the duplicate.
        if (identical(candidate, member)) ++j;
      } else {
        result[storeIndex++] = makeCandidate(member, setters);
        ++j;
      }
    }
    while (i < candidates.length) {
      result[storeIndex++] = candidates[i++];
    }
    while (j < members.length) {
      result[storeIndex++] = makeCandidate(members[j++], setters);
    }
    result.length = storeIndex;
    return result;
  }

  /// Transforms [member] into a candidate for interface inheritance.
  ///
  /// Fields are transformed into getters and setters; methods are passed
  /// through unchanged.
  static Procedure makeCandidate(Member member, bool setter) {
    if (member is Procedure) return member;
    if (member is Field) {
      // TODO(paulberry): don't set the type here, since it might not have been
      // inferred yet.  Instead, ensure that the field type is propagated to the
      // getter/setter during type inference.
      var type = member.type;
      if (setter) {
        var valueParam = new VariableDeclaration('_', type: type);
        var function = new FunctionNode(null,
            positionalParameters: [valueParam], returnType: const VoidType());
        return new SyntheticAccessor(
            member.name, ProcedureKind.Setter, function, member)
          ..parent = member.enclosingClass;
      } else {
        var function = new FunctionNode(null, returnType: type);
        return new SyntheticAccessor(
            member.name, ProcedureKind.Getter, function, member)
          ..parent = member.enclosingClass;
      }
    }
    return unhandled('${member.runtimeType}', 'makeCandidate', -1, null);
  }
}

/// A [SyntheticAccessor] represents the getter or setter implied by a field.
class SyntheticAccessor extends Procedure {
  /// The field associated with the synthetic accessor.
  final Field _field;

  SyntheticAccessor(
      Name name, ProcedureKind kind, FunctionNode function, this._field)
      : super(name, kind, function);
}
