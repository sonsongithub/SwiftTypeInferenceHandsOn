import SwiftcBasic

public final class ASTWalker : WalkerBase, ASTVisitor {
    public typealias VisitTarget = ASTNode
    public typealias VisitResult = WalkResult<ASTNode>
    
    public let _preWalk: (ASTNode, ASTContextNode) throws -> PreWalkResult<ASTNode>
    public let _postWalk: (ASTNode, ASTContextNode) throws -> WalkResult<ASTNode>
    
    public var context: ASTContextNode
    
    public init(context: ASTContextNode,
                preWalk: @escaping (ASTNode, ASTContextNode) throws -> PreWalkResult<ASTNode>,
                postWalk: @escaping (ASTNode, ASTContextNode) throws -> WalkResult<ASTNode>)
    {
        self.context = context
        _preWalk = preWalk
        _postWalk = postWalk
    }
    
    public func preWalk(_ target: ASTNode) throws -> PreWalkResult<ASTNode> {
        try _preWalk(target, context)
    }
    
    public func postWalk(_ target: ASTNode) throws -> WalkResult<ASTNode> {
        try _postWalk(target, context)
    }
    
    private func scope<R>(context: ASTContextNode, f: () throws -> R) rethrows -> R {
        let old = self.context
        self.context = context
        defer {
            self.context = old
        }
        return try f()
    }

    public func visitSourceFile(_ node: SourceFile) throws -> WalkResult<ASTNode> {
        try scope(context: node) {
            for i in 0..<node.statements.count {
                switch try process(node.statements[i]) {
                case .continue(let x):
                    node.statements[i] = x
                case .terminate:
                    return .terminate
                }
            }
            return .continue(node)
        }
    }
    
    public func visitFunctionDecl(_ node: FunctionDecl) throws -> WalkResult<ASTNode> {
        .continue(node)
    }
    
    public func visitVariableDecl(_ node: VariableDecl) throws -> WalkResult<ASTNode> {
        if let ie = node.initializer {
            switch try process(ie) {
            case .continue(let x):
                node.initializer = (x as! ASTExprNode)
            case .terminate:
                return .terminate
            }
        }
        
        return .continue(node)
    }
    
    public func visitCallExpr(_ node: CallExpr) throws -> WalkResult<ASTNode> {
        switch try process(node.callee) {
        case .continue(let x):
            node.callee = x
        case .terminate:
            return .terminate
        }
        
        switch try process(node.argument) {
        case .continue(let x):
            node.argument = x
        case .terminate:
            return .terminate
        }
        
        return .continue(node)
    }
    
    public func visitClosureExpr(_ node: ClosureExpr) throws -> WalkResult<ASTNode> {
        try scope(context: node) {
            switch try process(node.parameter) {
            case .continue(let x):
                node.parameter = (x as! VariableDecl)
            case .terminate:
                return .terminate
            }
            
            for i in 0..<node.body.count {
                switch try process(node.body[i]) {
                case .continue(let x):
                    node.body[i] = x
                case .terminate:
                    return .terminate
                }
            }

            return .continue(node)
        }
    }
    
    public func visitUnresolvedDeclRefExpr(_ node: UnresolvedDeclRefExpr) throws -> WalkResult<ASTNode> {
        .continue(node)
    }
    
    public func visitDeclRefExpr(_ node: DeclRefExpr) throws -> WalkResult<ASTNode> {
        .continue(node)
    }
    
    public func visitIntegerLiteralExpr(_ node: IntegerLiteralExpr) throws -> WalkResult<ASTNode> {
        .continue(node)
    }
}

extension ASTNode {
    @discardableResult
    public func walk(context: ASTContextNode,
                     preWalk: (ASTNode, ASTContextNode) throws -> PreWalkResult<ASTNode> =
        { (n, _) in .continue(n) },
                     postWalk: (ASTNode, ASTContextNode) throws -> WalkResult<ASTNode> =
        { (n, _) in .continue(n) })
        throws -> WalkResult<ASTNode>
    {
        try withoutActuallyEscaping(preWalk) { (preWalk) in
            try withoutActuallyEscaping(postWalk) { (postWalk) in
                let walker = ASTWalker(context: context,
                                       preWalk: preWalk,
                                       postWalk: postWalk)
                return try walker.process(self)
            }
        }
    }
}
