//
//  DependencyArguments.swift
//  
//
//  Created by Ömer Faruk Gökce on 1.07.2023.
//

import Foundation

/// In order to parametrize your dependency initialization you can use this  for your argument logic.
/// As this is a `@dynamicCallable` AND `@dynamicMemberLookup` type, you can use dynamic naming for your arguments when both creating and calling them.
/// Beware of the namings and types since this is all checked in run-time. Any misnaming or mistyping will result in fatal errors.
///
@dynamicCallable
@dynamicMemberLookup
public struct DependencyArguments {
    public static var arguments: DependencyArguments { .init() }
    
    internal var args: [String: Any]
    
    internal init(args: [String: Any] = [:]) {
        self.args = args
    }
    
    public func dynamicallyCall(withKeywordArguments args: [String: Any]) -> DependencyArguments {
        return .init(args: args)
    }
    
    public func dynamicallyCall(withArguments args: [Any]) -> DependencyArguments {
        var dict: [String: Any] = [:]
        for (i, arg) in args.enumerated() {
            dict["\(i)"] = arg
        }
        return .init(args: dict)
    }
    
    public subscript<Value>(dynamicMember key: String) -> Value {
        if let value = args[key] {
            if let value = value as? Value {
                return value
            } else {
                fatalError("Couldn't typecast the value for key \"\(key)\" to type \"\(Value.self)\"")
            }
        } else {
            fatalError("Couldn't find any value for key \"\(key)\"")
        }
    }
}
