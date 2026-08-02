//
//  Singleton.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.08.2026.
//

@attached(peer)
public macro Singleton() = #externalMacro(
    module: "ZerkMacros",
    type: "SingletonMacro"
)
