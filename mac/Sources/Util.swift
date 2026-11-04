// ddir macOS backend — small helpers shared by every command.
// JSON is built by hand (not JSONSerialization) so field order and shape stay
// byte-for-byte comparable with the Windows backend in src/main.rs.

import Foundation

let VERSION = "0.11.2"
let GAP = 16
let LEASE_TTL: UInt64 = 300

// MARK: - output

func es(_ s: String) -> String {
    var o = String()
    o.reserveCapacity(s.count + 8)
    for u in s.unicodeScalars {
        switch u {
        case "\"": o += "\\\""
        case "\\": o += "\\\\"
        case "\n": o += "\\n"
        case "\r": o += "\\r"
        case "\t": o += "\\t"
        default:
            if u.value < 0x20 {
                o += String(format: "\\u%04x", u.value)
            } else {
                o.unicodeScalars.append(u)
            }
        }
    }
    return o
}

func rectJSON(_ r: [Int]) -> String {
    "[\(r[0]),\(r[1]),\(r[2]),\(r[3])]"
}

func say(_ s: String) {
    print(s)
    fflush(stdout)
}

/// One-line JSON result. Agents parse this; nothing else may go to stdout.
func emit(_ s: String) {
    print(s)
    fflush(stdout)
}

// MARK: - args

func argValue(_ args: [String], _ name: String) -> String? {
    var i = 0
    while i < args.count {
        if args[i] == name, i + 1 < args.count {
            return args[i + 1]
        }
        if args[i].hasPrefix(name + "=") {
            return String(args[i].dropFirst(name.count + 1))
        }
        i += 1
    }
    return nil
}

func hasFlag(_ args: [String], _ name: String) -> Bool {
    args.contains(name)
}

func positional(_ args: [String]) -> [String] {
    args.filter { !$0.hasPrefix("--") }
}

func parseInt(_ s: String) -> Int? {
    Int(s.trimmingCharacters(in: .whitespaces))
}

/// "x,y,w,h" -> [x,y,w,h]
func parseRect(_ s: String) -> [Int]? {
    let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 4 else { return nil }
    var out: [Int] = []
    for p in parts {
        guard let v = Int(p) else { return nil }
        out.append(v)
    }
    return out
}

func formatRect(_ r: [Int]) -> String {
    "\(r[0]),\(r[1]),\(r[2]),\(r[3])"
}
