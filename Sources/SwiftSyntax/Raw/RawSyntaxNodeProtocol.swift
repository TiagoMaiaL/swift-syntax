//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// All typed raw syntax nodes conform to this protocol.
/// `RawXXXSyntax` is a typed wrappeer of `RawSyntax`.
@_spi(RawSyntax)
public protocol RawSyntaxNodeProtocol: CustomStringConvertible, TextOutputStreamable {
  /// Returns `true` if `raw` can be cast to this concrete raw syntax type.
  static func isKindOf(_ raw: RawSyntax) -> Bool

  /// Type erased raw syntax.
  var raw: RawSyntax { get }

  /// Create the typed raw syntax if `other` can be cast to `Self`
  init?(_ other: some RawSyntaxNodeProtocol)
}

public extension RawSyntaxNodeProtocol {
  /// Cast to the specified raw syntax type if possible.
  func `as`<Node: RawSyntaxNodeProtocol>(_: Node.Type) -> Node? {
    Node(self)
  }

  /// Check if this instance can be cast to the specified syntax type.
  func `is`<Node: RawSyntaxNodeProtocol>(_: Node.Type) -> Bool {
    Node.isKindOf(self.raw)
  }

  var description: String {
    raw.description
  }

  func write(to target: inout some TextOutputStream) {
    raw.write(to: &target)
  }

  var isEmpty: Bool {
    return raw.byteLength == 0
  }

  /// Whether the tree contained by this layout has any
  ///  - missing nodes or
  ///  - unexpected nodes or
  ///  - tokens with a `TokenDiagnostic` of severity `error`
  var hasError: Bool {
    return raw.recursiveFlags.contains(.hasError)
  }
}

/// `RawSyntax` itself conforms to `RawSyntaxNodeProtocol`.
extension RawSyntax: RawSyntaxNodeProtocol {
  public static func isKindOf(_ raw: RawSyntax) -> Bool {
    return true
  }
  public var raw: RawSyntax { self }

  init(raw: RawSyntax) {
    self = raw
  }

  public init(_ other: some RawSyntaxNodeProtocol) {
    self.init(raw: other.raw)
  }
}

#if swift(<5.8)
// Cherry-pick this function from SE-0370
extension Slice {
  @inlinable
  public func initialize<S>(
    from source: S
  ) -> (unwritten: S.Iterator, index: Index)
  where S: Sequence, Base == UnsafeMutableBufferPointer<S.Element> {
    let buffer = Base(rebasing: self)
    let (iterator, index) = buffer.initialize(from: source)
    let distance = buffer.distance(from: buffer.startIndex, to: index)
    return (iterator, startIndex.advanced(by: distance))
  }
}
#endif

@_spi(RawSyntax)
public struct RawTokenSyntax: RawSyntaxNodeProtocol {
  public typealias SyntaxType = TokenSyntax

  @_spi(RawSyntax)
  public var tokenView: RawSyntaxTokenView {
    return raw.tokenView!
  }

  public static func isKindOf(_ raw: RawSyntax) -> Bool {
    return raw.kind == .token
  }

  public var raw: RawSyntax

  init(raw: RawSyntax) {
    precondition(Self.isKindOf(raw))
    self.raw = raw
  }

  private init(unchecked raw: RawSyntax) {
    self.raw = raw
  }

  public init?(_ other: some RawSyntaxNodeProtocol) {
    guard Self.isKindOf(other.raw) else { return nil }
    self.init(unchecked: other.raw)
  }

  public var tokenKind: RawTokenKind {
    return tokenView.rawKind
  }

  public var tokenText: SyntaxText {
    return tokenView.rawText
  }

  public var byteLength: Int {
    return raw.byteLength
  }

  public var presence: SourcePresence {
    tokenView.presence
  }

  public var isMissing: Bool {
    presence == .missing
  }

  public var leadingTriviaByteLength: Int {
    return tokenView.leadingTriviaByteLength
  }

  public var leadingTriviaPieces: [RawTriviaPiece] {
    tokenView.leadingRawTriviaPieces
  }

  public var trailingTriviaByteLength: Int {
    return tokenView.trailingTriviaByteLength
  }

  public var trailingTriviaPieces: [RawTriviaPiece] {
    tokenView.trailingRawTriviaPieces
  }

  /// Creates a `RawTokenSyntax`. `wholeText` must be managed by the same
  /// `arena`. `textRange` is a range of the token text in `wholeText`.
  public init(
    kind: RawTokenKind,
    wholeText: SyntaxText,
    textRange: Range<SyntaxText.Index>,
    presence: SourcePresence,
    tokenDiagnostic: TokenDiagnostic?,
    arena: __shared SyntaxArena
  ) {
    let raw = RawSyntax.parsedToken(
      kind: kind,
      wholeText: wholeText,
      textRange: textRange,
      presence: presence,
      tokenDiagnostic: tokenDiagnostic,
      arena: arena
    )
    self = RawTokenSyntax(unchecked: raw)
  }

  /// Creates a `RawTokenSyntax`. `text` and trivia must be managed by the same
  /// `arena`.
  public init(
    kind: RawTokenKind,
    text: SyntaxText,
    leadingTriviaPieces: [RawTriviaPiece] = [],
    trailingTriviaPieces: [RawTriviaPiece] = [],
    presence: SourcePresence,
    tokenDiagnostic: TokenDiagnostic? = nil,
    arena: __shared SyntaxArena
  ) {
    if leadingTriviaPieces.isEmpty && trailingTriviaPieces.isEmpty {
      // Create it via `RawSyntax.parsedToken()`.
      self.init(
        kind: kind,
        wholeText: text,
        textRange: 0..<text.count,
        presence: presence,
        tokenDiagnostic: tokenDiagnostic,
        arena: arena
      )
    } else {
      // Create it via `RawSyntax.makeMaterializedToken()`.
      self.init(
        materialized: kind,
        text: text,
        leadingTriviaPieces: leadingTriviaPieces,
        trailingTriviaPieces: trailingTriviaPieces,
        presence: presence,
        tokenDiagnostic: tokenDiagnostic,
        arena: arena
      )
    }
  }

  /// Creates a `MaterializedToken`. Trivia must be managed by the same `arena`.
  fileprivate init(
    materialized kind: RawTokenKind,
    text: SyntaxText,
    leadingTriviaPieces: [RawTriviaPiece],
    trailingTriviaPieces: [RawTriviaPiece],
    presence: SourcePresence,
    tokenDiagnostic: TokenDiagnostic?,
    arena: __shared SyntaxArena
  ) {
    let raw = RawSyntax.makeMaterializedToken(
      kind: kind,
      text: text,
      leadingTriviaPieceCount: leadingTriviaPieces.count,
      trailingTriviaPieceCount: trailingTriviaPieces.count,
      presence: presence,
      tokenDiagnostic: tokenDiagnostic,
      arena: arena,
      initializingLeadingTriviaWith: { buffer in
        _ = buffer.initialize(from: leadingTriviaPieces)
      },
      initializingTrailingTriviaWith: { buffer in
        _ = buffer.initialize(from: trailingTriviaPieces)
      }
    )
    self = RawTokenSyntax(unchecked: raw)
  }

  /// Creates a missing `TokenSyntax` with the specified kind.
  /// If `text` is passed, it will be used to represent the missing token's text.
  /// If `text` is `nil`, the `kind`'s default text will be used.
  /// If that is also `nil`, the token will have empty text.
  public init(
    missing kind: RawTokenKind,
    text: SyntaxText? = nil,
    leadingTriviaPieces: [RawTriviaPiece] = [],
    trailingTriviaPieces: [RawTriviaPiece] = [],
    arena: __shared SyntaxArena
  ) {
    // FIXME: Allow creating a `RawSyntax.parsedToken()` with a string literal
    // for text. Currently it asserts that the string buffer is not contained
    // within the `arena`.
    self.init(
      materialized: kind,
      text: text ?? kind.defaultText ?? "",
      leadingTriviaPieces: leadingTriviaPieces,
      trailingTriviaPieces: trailingTriviaPieces,
      presence: .missing,
      tokenDiagnostic: nil,
      arena: arena
    )
  }
}
