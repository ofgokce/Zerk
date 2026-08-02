//
//  Shared.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

@attached(peer)
public macro Shared() = #externalMacro(
    module: "ZerkMacros",
    type: "SharedMacro"
)

@attached(peer)
public macro Shared<each T>() = #externalMacro(
    module: "ZerkMacros",
    type: "SharedMacro"
)
