import Foundation

/// Minimal NumPy `.npy` reader — enough for the Phase 0 fixtures written by
/// `scripts/export_fixtures.py` (little-endian float32, C order, 1–3 dims).
struct NPY {
    let shape: [Int]
    let floats: [Float]

    enum NPYError: Error, CustomStringConvertible {
        case badMagic
        case unsupportedVersion(UInt8)
        case badHeader(String)
        case unsupportedDescriptor(String)
        case unsupportedOrder
        case truncated

        var description: String {
            switch self {
            case .badMagic: return "not a .npy file"
            case .unsupportedVersion(let major): return "unsupported .npy version \(major)"
            case .badHeader(let header): return "cannot parse .npy header: \(header)"
            case .unsupportedDescriptor(let descriptor): return "unsupported dtype \(descriptor)"
            case .unsupportedOrder: return "Fortran-order arrays are not supported"
            case .truncated: return "truncated .npy payload"
            }
        }
    }

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count >= 10, data[0] == 0x93, data[1...5].elementsEqual("NUMPY".utf8) else {
            throw NPYError.badMagic
        }
        let major = data[6]
        let headerLength: Int
        let headerStart: Int
        if major == 1 {
            headerLength = Int(data[8]) | (Int(data[9]) << 8)
            headerStart = 10
        } else if major == 2 || major == 3 {
            guard data.count >= 12 else { throw NPYError.truncated }
            headerLength = Int(data[8]) | (Int(data[9]) << 8) | (Int(data[10]) << 16) | (Int(data[11]) << 24)
            headerStart = 12
        } else {
            throw NPYError.unsupportedVersion(major)
        }
        guard headerStart + headerLength <= data.count else { throw NPYError.truncated }
        let header = String(decoding: data.subdata(in: headerStart..<(headerStart + headerLength)),
                            as: UTF8.self)

        guard let descriptor = Self.value(in: header, key: "descr") else {
            throw NPYError.badHeader(header)
        }
        guard ["<f4", "=f4", "|f4"].contains(descriptor) else {
            throw NPYError.unsupportedDescriptor(descriptor)
        }
        guard Self.value(in: header, key: "fortran_order") == "False" else {
            throw NPYError.unsupportedOrder
        }
        guard let shapeString = Self.value(in: header, key: "shape") else {
            throw NPYError.badHeader(header)
        }
        let dims = shapeString
            .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        self.shape = dims

        let count = dims.reduce(1, *)
        let payload = data.subdata(in: (headerStart + headerLength)..<data.count)
        guard payload.count >= count * 4 else { throw NPYError.truncated }
        var floats = [Float](repeating: 0, count: count)
        payload.withUnsafeBytes { raw in
            for i in 0..<count {
                let bits = raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                floats[i] = Float(bitPattern: UInt32(littleEndian: bits))
            }
        }
        self.floats = floats
    }

    /// Reads a `'key': value` pair from the header dict (string, tuple, or bare literal).
    private static func value(in header: String, key: String) -> String? {
        guard let keyRange = header.range(of: "'\(key)':") else { return nil }
        var rest = header[keyRange.upperBound...].drop(while: { $0 == " " })
        guard let first = rest.first else { return nil }
        if first == "'" {
            rest = rest.dropFirst()
            guard let closing = rest.firstIndex(of: "'") else { return nil }
            return String(rest[..<closing])
        }
        if first == "(" {
            guard let closing = rest.firstIndex(of: ")") else { return nil }
            return String(rest[..<closing])
        }
        // Bare literal (False / True / None): up to comma, brace, or space.
        let end = rest.firstIndex(where: { $0 == "," || $0 == "}" || $0 == " " }) ?? rest.endIndex
        return String(rest[..<end])
    }
}
