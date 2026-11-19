import Foundation

/// Packing of 五笔 codes into a single scalar so that lookups are a binary
/// search over a contiguous array instead of string hashing.
///
/// A code is four base-27 digits (a..z -> 1..26, absent -> 0), so "abc"
/// becomes 1*27^3 + 2*27^2 + 3*27 + 0. Because the digits are zero-padded,
/// numeric order equals lexicographic order and every prefix maps onto a
/// contiguous range -- exact lookups and prefix probes are both plain binary
/// searches over the same array.
public enum WubiCode {
    public static let maxCodeLength = 4

    @inline(__always)
    static func digit(_ c: Character) -> UInt32 {
        guard let ascii = c.asciiValue, ascii >= 97, ascii <= 122 else { return 0 }
        return UInt32(ascii - 96)
    }

    /// Returns 0 (an invalid key) when the code contains non a-z bytes.
    public static func pack(_ code: String) -> UInt32 {
        var value: UInt32 = 0
        var index = 0
        for character in code {
            let d = digit(character)
            if d == 0 { return 0 }
            value = value * 27 + d
            index += 1
            if index == maxCodeLength { break }
        }
        guard index > 0 else { return 0 }
        while index < maxCodeLength {
            value *= 27
            index += 1
        }
        return value
    }

    public static func unpack(_ value: UInt32) -> String {
        var digits = [UInt32](repeating: 0, count: maxCodeLength)
        var rest = value
        for index in stride(from: maxCodeLength - 1, through: 0, by: -1) {
            digits[index] = rest % 27
            rest /= 27
        }
        var scalars = String.UnicodeScalarView()
        for d in digits where d > 0 {
            scalars.append(Unicode.Scalar(UInt8(96 + d)))
        }
        return String(scalars)
    }

    /// Inclusive numeric range covering every code that starts with a prefix.
    public static func prefixRange(_ prefix: String) -> ClosedRange<UInt32> {
        let packed = pack(prefix)
        var span: UInt32 = 1
        var remaining = maxCodeLength - prefix.count
        while remaining > 0 {
            span *= 27
            remaining -= 1
        }
        let low = packed
        return low...(low + span - 1)
    }
}
