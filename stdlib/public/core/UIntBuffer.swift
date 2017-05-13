//===--- UIntBuffer.swift - Bounded Collection of Unsigned Integer --------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
//  Stores a smaller unsigned integer type inside a larger one, with a limit of
//  255 elements.
//
//===----------------------------------------------------------------------===//
@_fixed_layout
public struct _UIntBuffer<
  Storage: UnsignedInteger & FixedWidthInteger, 
  Element: UnsignedInteger & FixedWidthInteger
> {
  public var _storage: Storage
  public var _bitCount: UInt8

  @inline(__always)
  public init(_storage: Storage, _bitCount: UInt8) {
    self._storage = _storage
    self._bitCount = _bitCount
  }
  
  @inline(__always)
  public init(containing e: Element) {
    _storage = Storage(extendingOrTruncating: e)
    _bitCount = UInt8(extendingOrTruncating: Element.bitWidth)
  }
}

extension _UIntBuffer : Sequence {
  public typealias SubSequence = RangeReplaceableRandomAccessSlice<_UIntBuffer>
  
  @_fixed_layout
  public struct Iterator : IteratorProtocol, Sequence {
    @inline(__always)
    public init(_ x: _UIntBuffer) { _impl = x }
    
    @inline(__always)
    public mutating func next() -> Element? {
      if _impl._bitCount == 0 { return nil }
      defer {
        _impl._storage = _impl._storage &>> Element.bitWidth
        _impl._bitCount = _impl._bitCount &- _impl._elementWidth
      }
      return Element(extendingOrTruncating: _impl._storage)
    }
    public
    var _impl: _UIntBuffer
  }
  
  @inline(__always)
  public func makeIterator() -> Iterator {
    return Iterator(self)
  }
}

extension _UIntBuffer : Collection {
  public typealias _Element = Element
  
  public struct Index : Comparable {
    @_versioned
    var bitOffset: UInt8
    
    @_versioned
    init(bitOffset: UInt8) { self.bitOffset = bitOffset }
    
    public static func == (lhs: Index, rhs: Index) -> Bool {
      return lhs.bitOffset == rhs.bitOffset
    }
    public static func < (lhs: Index, rhs: Index) -> Bool {
      return lhs.bitOffset < rhs.bitOffset
    }
  }

  public var startIndex : Index {
    @inline(__always)
    get { return Index(bitOffset: 0) }
  }
  
  public var endIndex : Index {
    @inline(__always)
    get { return Index(bitOffset: _bitCount) }
  }
  
  @inline(__always)
  public func index(after i: Index) -> Index {
    return Index(bitOffset: i.bitOffset &+ _elementWidth)
  }

  @_versioned
  internal var _elementWidth : UInt8 {
    return UInt8(extendingOrTruncating: Element.bitWidth)
  }
  
  public subscript(i: Index) -> Element {
    @inline(__always)
    get {
      return Element(extendingOrTruncating: _storage &>> i.bitOffset)
    }
  }
}

extension _UIntBuffer : BidirectionalCollection {
  @inline(__always)
  public func index(before i: Index) -> Index {
    return Index(bitOffset: i.bitOffset &- _elementWidth)
  }
}

extension _UIntBuffer : RandomAccessCollection {
  public typealias Indices = DefaultRandomAccessIndices<_UIntBuffer>
  public typealias IndexDistance = Int
  
  @inline(__always)
  public func index(_ i: Index, offsetBy n: IndexDistance) -> Index {
    let x = IndexDistance(i.bitOffset) &+ n &* Element.bitWidth
    return Index(bitOffset: UInt8(extendingOrTruncating: x))
  }

  @inline(__always)
  public func distance(from i: Index, to j: Index) -> IndexDistance {
    return (Int(j.bitOffset) &- Int(i.bitOffset)) / Element.bitWidth
  }
}

extension FixedWidthInteger {
  @inline(__always)
  @_versioned
  func _fullShiftLeft<N: FixedWidthInteger>(_ n: N) -> Self {
    return (self &<< ((n &+ 1) &>> 1)) &<< (n &>> 1)
  }
  @inline(__always)
  @_versioned
  func _fullShiftRight<N: FixedWidthInteger>(_ n: N) -> Self {
    return (self &>> ((n &+ 1) &>> 1)) &>> (n &>> 1)
  }
  @inline(__always)
  @_versioned
  static func _lowBits<N: FixedWidthInteger>(_ n: N) -> Self {
    return ~((~0 as Self)._fullShiftLeft(n))
  }
}

extension Range {
  @inline(__always)
  @_versioned
  func _contains_(_ other: Range) -> Bool {
    return other.clamped(to: self) == other
  }
}

extension _UIntBuffer : RangeReplaceableCollection {
  @inline(__always)
  public init() {
    _storage = 0
    _bitCount = 0
  }

  public var capacity: Int {
    return Storage.bitWidth / Element.bitWidth
  }

  @inline(__always)
  public mutating func append(_ newElement: Element) {
    _debugPrecondition(count + 1 <= capacity)
    _storage |= Storage(newElement) &<< _bitCount
    _bitCount = _bitCount &+ _elementWidth
  }
  
  @inline(__always)
  public mutating func replaceSubrange<C: Collection>(
    _ target: Range<Index>, with replacement: C
  ) where C._Element == Element {
    _debugPrecondition(
      (0..<_bitCount)._contains_(
        target.lowerBound.bitOffset..<target.upperBound.bitOffset))
    
    let replacement1 = _UIntBuffer(replacement)

    let targetCount = distance(
      from: target.lowerBound, to: target.upperBound)
    let growth = replacement1.count &- targetCount
    _debugPrecondition(count + growth <= capacity)

    let headCount = distance(from: startIndex, to: target.lowerBound)
    let tailOffset = distance(from: startIndex, to: target.upperBound)

    let w = Element.bitWidth
    let headBits = _storage & ._lowBits(headCount &* w)
    let tailBits = _storage._fullShiftRight(tailOffset &* w)

    _storage = headBits
    _storage |= replacement1._storage &<< (headCount &* w)
    _storage |= tailBits &<< ((tailOffset &+ growth) &* w)
    _bitCount = UInt8(
      extendingOrTruncating: IndexDistance(_bitCount) &+ growth &* w)
  }
}