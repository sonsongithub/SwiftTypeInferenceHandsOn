import SwiftcType

public struct TypeVariableBindings {
    /**
     自分が代表の場合free, fixed、代表転送を持つ場合はtransfer
     */
    public enum Binding {
        case free
        case fixed(Type)
        case transfer(TypeVariable)
    }
    
    public private(set) var map: [TypeVariable: Binding] = [:]
    
    public init() {}
    
    public func binding(for variable: TypeVariable) -> Binding {
        map[variable] ?? .free
    }
    public mutating func setBinding(for variable: TypeVariable, _ binding: Binding) {
        map[variable] = binding
    }
    
    public mutating func merge(type1: TypeVariable,
                               type2: TypeVariable)
    {
        precondition(type1.isRepresentative(bindings: self))
        precondition(type1.fixedType(bindings: self) == nil)
        precondition(type2.isRepresentative(bindings: self))
        precondition(type2.fixedType(bindings: self) == nil)
        
        if type1 == type2 {
            return
        }
        
        // <Q03 hint="understand data structure" />
        if type1.id > type2.id {
            switch map[type2] {
            case .transfer(let rep):
                setBinding(for: type1, .transfer(rep))
            default:
                setBinding(for: type1, .transfer(type2))
            }
            
            // type1を指してるやつをtype2へ変える
            for (tv, b) in map {
                switch b {
                case .transfer(let rep):
                    if rep == type1 { map[tv] = .transfer(type2) }
                default:
                    do {}
                }
            }
        } else {
            switch map[type1] {
            case .transfer(let rep):
                setBinding(for: type2, .transfer(rep))
            default:
                setBinding(for: type2, .transfer(type1))
            }
            
            // type2を指してるやつをtype1へ変える
            for (tv, b) in map {
                switch b {
                case .transfer(let rep):
                    if rep == type2 { map[tv] = .transfer(type1) }
                default:
                    do {}
                }
            }
        }
        print(map)
    }
    
    public mutating func assign(variable: TypeVariable,
                                type: Type)
    {
        precondition(variable.isRepresentative(bindings: self))
        precondition(variable.fixedType(bindings: self) == nil)
        precondition(!(type is TypeVariable))
        
        map[variable] = .fixed(type)
    }
}

extension TypeVariable {
    public func isRepresentative(bindings: TypeVariableBindings) -> Bool {
        representative(bindings: bindings) == self
    }
    
    public func representative(bindings: TypeVariableBindings) -> TypeVariable {
        switch bindings.binding(for: self) {
        case .free,
             .fixed:
            return self
        case .transfer(let rep):
            return rep
        }
    }
    
    public func fixedType(bindings: TypeVariableBindings) -> Type? {
        switch bindings.binding(for: self) {
        case .free:
            return nil
        case .fixed(let ft):
            return ft
        case .transfer(let rep):
            return rep.fixedType(bindings: bindings)
        }
    }
    
    public func fixedOrRepresentative(bindings: TypeVariableBindings) -> Type {
        switch bindings.binding(for: self) {
        case .free:
            return self
        case .fixed(let ft):
            return ft
        case .transfer(let rep):
            return rep.fixedOrRepresentative(bindings: bindings)
        }
    }
    
    public func equivalentTypeVariables(bindings: TypeVariableBindings) -> Set<TypeVariable> {
        var ret = Set<TypeVariable>()
        for (tv, b) in bindings.map {
            switch b {
            case .free,
                 .fixed:
                if tv == self { ret.insert(tv) }
            case .transfer(let rep):
                if rep == self { ret.insert(tv) }
            }
        }
        return ret
    }
    
    public func isFree(bindings: TypeVariableBindings) -> Bool {
        switch bindings.binding(for: self) {
        case .free: return true
        case .fixed,
             .transfer: return false
        }
    }
}

extension Type {
    public func simplify(bindings: TypeVariableBindings) -> Type {
        transform { (type) in
            if let tv = type as? TypeVariable {
                var type = tv.fixedOrRepresentative(bindings: bindings)
                if !(type is TypeVariable) {
                    type = type.simplify(bindings: bindings)
                }
                return type
            }
             
            return nil
        }
    }
}
