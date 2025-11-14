import Foundation

// Swift stdlib demangler (not public API but stable)
@_silgen_name("swift_demangle")
private func _stdlib_demangleImpl(
    _ mangledName: UnsafePointer<CChar>?,
    mangledNameLength: UInt,
    outputBuffer: UnsafeMutablePointer<UInt8>?,
    outputBufferSize: UnsafeMutablePointer<UInt>?,
    flags: UInt32
) -> UnsafeMutablePointer<CChar>?

/// Utilities for demangling Swift and C++ symbol names.
public enum Demangler {
    /// Attempts to demangle a Swift or C++ mangled symbol name.
    /// Returns the demangled name, or the original name if demangling fails.
    public static func demangle(_ mangledName: String) -> String {
        // Try Swift demangling first (for symbols starting with _T, $S, $s, etc.)
        if mangledName.hasPrefix("_T") || mangledName.hasPrefix("$S") ||
           mangledName.hasPrefix("$s") || mangledName.hasPrefix("_$s") {
            if let demangled = demangleSwift(mangledName) {
                return demangled
            }
        }

        // Try C++ demangling (for symbols starting with _Z)
        if mangledName.hasPrefix("_Z") {
            if let demangled = demangleCpp(mangledName) {
                return demangled
            }
        }

        // Return original if demangling failed
        return mangledName
    }

    /// Demangles a Swift symbol using the Swift stdlib's built-in demangler.
    private static func demangleSwift(_ mangledName: String) -> String? {
        mangledName.withCString { mangledNamePtr in
            guard let demangledNamePtr = _stdlib_demangleImpl(
                mangledNamePtr,
                mangledNameLength: UInt(strlen(mangledNamePtr)),
                outputBuffer: nil,
                outputBufferSize: nil,
                flags: 0
            ) else {
                return nil
            }

            let demangledName = String(cString: demangledNamePtr)
            free(demangledNamePtr)
            return demangledName
        }
    }

    /// Demangles a C++ symbol using the C++ ABI demangler (if available).
    private static func demangleCpp(_ mangledName: String) -> String? {
        #if os(macOS) || os(Linux)
        return mangledName.withCString { mangledNamePtr in
            var status: Int32 = 0
            guard let demangledNamePtr = __cxa_demangle(
                mangledNamePtr,
                nil,
                nil,
                &status
            ), status == 0 else {
                return nil
            }

            let demangledName = String(cString: demangledNamePtr)
            free(demangledNamePtr)
            return demangledName
        }
        #else
        return nil
        #endif
    }
}

// C++ ABI demangler
#if os(macOS) || os(Linux)
@_silgen_name("__cxa_demangle")
private func __cxa_demangle(
    _ mangledName: UnsafePointer<CChar>?,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ length: UnsafeMutablePointer<Int>?,
    _ status: UnsafeMutablePointer<Int32>?
) -> UnsafeMutablePointer<CChar>?
#endif
