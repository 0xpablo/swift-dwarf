import DWARF

extension DWARFDie {
    func symbolicatedDisplayName() -> String {
        if let linkage = (try? linkageName()) ?? nil {
            let demangled = Demangler.demangle(linkage)
            if demangled != linkage {
                return demangled
            }
        }
        if let simple = (try? name()) ?? nil {
            return Demangler.stripSwiftPrivateContext(from: simple)
        }
        return "(unknown)"
    }
}
