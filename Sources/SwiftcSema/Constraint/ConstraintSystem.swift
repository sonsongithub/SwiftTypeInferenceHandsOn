import Foundation
import SwiftcBasic
import SwiftcType
import SwiftcAST

public final class ConstraintSystem {
    public enum SolveResult {
        case solved
        case failure
        case ambiguous
    }
    
    public struct MatchOptions {
        public var generateConstraintsWhenAmbiguous: Bool = false
        
        public init() {}
    }
    
    public struct Solution {
        public var bindings: TypeVariableBindings
        public var astTypes: [ObjectIdentifier: Type]
        
        public init(bindings: TypeVariableBindings,
                    astTypes: [ObjectIdentifier: Type])
        {
            self.bindings = bindings
            self.astTypes = astTypes
        }
        
        public func fixedType(for node: ASTNode) -> Type? {
            guard let ty = astTypes[ObjectIdentifier(node)] else {
                return nil
            }
            if let tv = ty as? TypeVariable {
                return tv.fixedType(bindings: bindings)
            } else {
                return ty
            }
        }
    }

    public private(set) var typeVariables: [TypeVariable] = []
    public private(set) var bindings: TypeVariableBindings = TypeVariableBindings()
    public private(set) var astTypes: [ObjectIdentifier: Type] = [:]
    
    public private(set) var failedConstraint: ConstraintEntry?
    
    public private(set) var constraints: [ConstraintEntry] = []
    
    public init() {}
    
    deinit {
    }
    
    public func createTypeVariable() -> TypeVariable {
        let id = typeVariables.count + 1
        let tv = TypeVariable(id: id)
        bindings.setBinding(for: tv, .fixed(nil))
        typeVariables.append(tv)
        return tv
    }
    
    public func createTypeVariable(for node: ASTNode) -> TypeVariable {
        let tv = createTypeVariable()
        setASTType(for: node, tv)
        return tv
    }
    
    public func normalize() {
        for (node, type) in astTypes {
            astTypes[node] = simplify(type: type)
        }
    }
    
    public func doAllTypeVariablesHaveFixedType() -> Bool {
        return bindings.doAllTypeVariablesHaveFixedType()
    }
    
    public func currentSolution() -> Solution {
        return Solution(bindings: bindings,
                        astTypes: astTypes)
    }
    
    public func _addAmbiguousConstraint(_ constraint: Constraint) {
        let entry = ConstraintEntry(constraint)
        constraints.append(entry)
    }
    
    /**
     型に含まれる型変数を再帰的に置換した型を返す。
     固定型の割当がない場合は代表型変数に置換する。
     */
    public func simplify(type: Type) -> Type {
        type.simplify(bindings: bindings)
    }

    public func fixedOrRepresentative(for typeVariable: TypeVariable) -> Type {
        typeVariable.fixedOrRepresentative(bindings: bindings)
    }
    
    public func mergeEquivalence(type1: TypeVariable,
                                 type2: TypeVariable)
    {
        bindings.merge(type1: type1, type2: type2)
    }
    
    public func assignFixedType(variable: TypeVariable,
                                type: Type)
    {
        bindings.assign(variable: variable, type: type)
    }
    
    public func astType(for node: ASTNode) -> Type? {
        if let type = astTypes[ObjectIdentifier(node)] {
            return type
        }
        
        if let ex = node as? ASTExprNode {
            return ex.type
        }
        
        if let ctx = node as? ASTContextNode {
            return ctx.interfaceType
        }
        
        return nil
    }
    
    public func setASTType(for node: ASTNode, _ type: Type) {
        astTypes[ObjectIdentifier(node)] = type
    }
    
    public func addConstraint(_ constraint: Constraint) {
        func submit() -> SolveResult {
            var options = MatchOptions()
            options.generateConstraintsWhenAmbiguous = true
            switch constraint {
            case .bind(left: let left, right: let right):
                return matchTypes(left: left, right: right,
                                  kind: constraint.kind, options: options)
            case .applicableFunction(left: let left, right: let right):
                return simplifyApplicableFunctionConstraint(left: left,
                                                            right: right,
                                                            options: options)
            }
        }
    
        switch submit() {
        case .solved:
            break
        case .failure:
            if failedConstraint == nil {
                failedConstraint = ConstraintEntry(constraint)
            }
            
            break
        case .ambiguous:
            fatalError("addConstraint forbids ambiguous")
        }
    }

    public func matchTypes(left: Type,
                           right: Type,
                           kind: Constraint.Kind,
                           options: MatchOptions) -> SolveResult
    {
        let left = simplify(type: left)
        let right = simplify(type: right)
        
        let leftVar = left as? TypeVariable
        let rightVar = right as? TypeVariable
        
        if leftVar != nil || rightVar != nil {
            if let left = leftVar, let right = rightVar {
                return matchTypeVariables(left: left,
                                          right: right,
                                          kind: kind)
            }
            
            var variable: TypeVariable!
            var type: Type!
            
            if let left = leftVar {
                variable = left
                type = right
            } else {
                variable = rightVar!
                type = left
            }
            
            return matchTypeVariableAndFixedType(variable: variable,
                                                 type: type,
                                                 kind: kind)
        }
        
        return matchFixedTypes(type1: left, type2: right,
                               kind: kind, options: options)
    }
    
    private func matchTypeVariables(left: TypeVariable,
                                    right: TypeVariable,
                                    kind: Constraint.Kind) -> SolveResult
    {
        precondition(left.isRepresentative(bindings: bindings))
        precondition(right.isRepresentative(bindings: bindings))
        
        if left == right {
            return .solved
        }
        
        switch kind {
        case .bind:
            mergeEquivalence(type1: left, type2: right)
            return .solved
        case .applicableFunction:
            preconditionFailure("invalid kind: \(kind)")
        }
    }
    
    private func matchTypeVariableAndFixedType(variable: TypeVariable,
                                               type: Type,
                                               kind: Constraint.Kind) -> SolveResult
    {
        precondition(variable.isRepresentative(bindings: bindings))
        switch kind {
        case .bind:            
            if variable.occurs(in: type) {
                return .failure
            }
            
            assignFixedType(variable: variable, type: type)
            return .solved
        case .applicableFunction:
            preconditionFailure("invalid kind: \(kind)")
        }
    }
    
    private func matchFixedTypes(type1: Type,
                                 type2: Type,
                                 kind: Constraint.Kind,
                                 options: MatchOptions) -> SolveResult
    {
        precondition(!(type1 is TypeVariable))
        precondition(!(type2 is TypeVariable))
        
        switch kind {
        case .bind:
            if let type1 = type1 as? PrimitiveType {
                guard let type2 = type2 as? PrimitiveType else {
                    return .failure
                }
                
                if type1.name == type2.name {
                    return .solved
                } else {
                    return .failure
                }
            }
            
            if let type1 = type1 as? FunctionType {
                guard let type2 = type2 as? FunctionType else {
                    return .failure
                }
                
                return matchFunctionTypes(type1: type1, type2: type2,
                                          kind: kind, options: options)
            }
            
            unimplemented()
        case .applicableFunction:
            preconditionFailure("invalid kind: \(kind)")
        }
    }
    
    private func matchFunctionTypes(type1: FunctionType,
                                    type2: FunctionType,
                                    kind: Constraint.Kind,
                                    options: MatchOptions) -> SolveResult
    {
        let arg1 = type1.parameter
        let arg2 = type2.parameter
        
        let ret1 = type1.result
        let ret2 = type2.result
        
        var isAmbiguous = false
        
        switch kind {
        case .bind:
            switch matchTypes(left: arg1, right: arg2,
                              kind: kind, options: options)
            {
            case .failure: return .failure
            case .ambiguous:
                isAmbiguous = true
                break
            case .solved: break
            }
            
            switch matchTypes(left: ret1, right: ret2,
                              kind: kind, options: options)
            {
            case .failure: return .failure
            case .ambiguous:
                isAmbiguous = true
                break
            case .solved: break
            }
            
            if isAmbiguous {
                return .ambiguous
            } else {
                return .solved
            }
        case .applicableFunction:
            preconditionFailure("invalid kind: \(kind)")
        }
    }
}
