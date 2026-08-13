//
//  StringExt.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

extension String {
    /// The member name a type name gives: the identifier the generated member
    /// exposing that type is declared under.
    ///
    /// | type | member |
    /// |---|---|
    /// | `ApiService` | `apiService` |
    /// | `URLSession` | `urlSession` |
    /// | `HTTPClient` | `httpClient` |
    /// | `UTF8Decoder` | `utf8Decoder` |
    /// | `URL` | `url` |
    /// | `Keychain.Store` | `store` |
    ///
    /// Two things happen, and both are about producing a name a developer would
    /// have written themselves.
    ///
    /// A qualification says where a type lives rather than what it is called,
    /// and `keychain.Store` is not an identifier — so only the last component
    /// survives. Nothing but a nested type reaches this with a dot in it.
    ///
    /// And an acronym that *begins* the name is lowercased whole, per the Swift
    /// API Design Guidelines. Lowercasing the first character alone turns
    /// `URLSession` into `uRLSession`, which reads as a typo rather than as a
    /// name.
    var memberNameForType: String {
        let base = split(separator: ".").last.map(String.init) ?? self
        return base.lowercasingLeadingAcronym
    }

    /// Lowercases the run of capitals the name opens with, leaving the first
    /// word boundary where it belongs.
    ///
    /// The last capital of a run usually begins the *next* word — `URLSession`
    /// is `URL` + `Session`, so the `S` has to survive. That does not hold when
    /// the run is the whole name (`URL`), when a digit follows it
    /// (`UTF8Decoder`), or when what follows is a single letter rather than a
    /// word.
    ///
    /// That last case is a heuristic, and the one place this cannot be exact:
    /// `URLs` is a plural and `URLId` is two words, and nothing in the spelling
    /// tells them apart. It resolves in favour of the plural, which is the far
    /// more likely type name — so `URLs` gives `urls`, and a type genuinely
    /// spelled `URLId` gives `urlid`. Write the member name out with
    /// `@Injectable(name:)` if a name lands on the wrong side of this.
    private var lowercasingLeadingAcronym: String {
        let characters = Array(self)
        let run = characters.prefix { $0.isUppercase }.count

        guard run > 0 else {
            return self
        }
        guard run > 1 else {
            return characters[0].lowercased() + String(characters.dropFirst())
        }

        let remainder = characters.count - run
        let lastCapitalStartsAWord = remainder >= 2 && characters[run].isLowercase
        let lowered = lastCapitalStartsAWord ? run - 1 : run

        return String(characters[..<lowered]).lowercased() + String(characters[lowered...])
    }

    /// Uppercases the first character only, for splicing a name into the middle
    /// of another: `foo` -> `Foo`, so `value` + `foo` reads `valueFoo`.
    ///
    /// No acronym rule here, deliberately: this splices an already-lowerCamel
    /// *parameter* name into the middle of an identifier, where a leading
    /// acronym is not at the start of anything.
    var upperCamelCased: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

}
