//
//  Injected.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

@attached(peer, names: prefixed(_$zerk_injection_))
public macro Injected() = #externalMacro(
    module: "ZerkMacros",
    type: "InjectedMacro"
)

@attached(peer, names: prefixed(_$zerk_injection_))
public macro Injected<T>(_ injectable: T) = #externalMacro(
    module: "ZerkMacros",
    type: "InjectedMacro"
)
