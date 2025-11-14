import Foundation
import Testing
@testable import DWARFSymbolication

struct DemanglerTests {
    // MARK: - Swift Demangling Tests

    @Test
    func demangleSwiftFunction() {
        let mangled = "$s11TestProgram5greet4nameS2S_tF"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled == "TestProgram.greet(name: Swift.String) -> Swift.String")
        #expect(demangled != mangled, "Should successfully demangle")
    }

    @Test
    func demangleSwiftTypeMetadataAccessor() {
        let mangled = "$s13GoodNotesCore12RocksDBCacheCMa"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled == "type metadata accessor for GoodNotesCore.RocksDBCache")
        #expect(demangled != mangled)
    }

    @Test
    func demangleSwiftExtensionMethod() {
        let mangled = "$sSo7RocksDBC13GoodNotesCoreE11healthCheckyyKF"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled == "(extension in GoodNotesCore):__C.RocksDB.healthCheck() throws -> ()")
        #expect(demangled != mangled)
    }

    @Test
    func demangleSwiftValueWitness() {
        let mangled = "$s13GoodNotesCore14RocksDBFactoryC11StorageTypeOwCP"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled == "initializeBufferWithCopyOfBuffer value witness for GoodNotesCore.RocksDBFactory.StorageType")
        #expect(demangled != mangled)
    }

    @Test
    func demangleSwiftClosure() {
        let mangled = "$s13GoodNotesCore12RocksDBCacheC5cacheSoABCSgvgAFyYbXEfU_TA"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled.contains("partial apply forwarder"))
        #expect(demangled.contains("closure"))
        #expect(demangled != mangled)
    }

    @Test
    func demangleSwiftOldMangling() {
        // Test older Swift mangling schemes (_T, _$s)
        let mangled = "_$s9GNAppInfo03AppB0VWOh"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled != mangled, "Should demangle older Swift symbols")
    }

    // MARK: - C++ Demangling Tests

    @Test
    func demangleCppDestructor() {
        let mangled = "_ZN7rocksdb9DBOptionsD2Ev"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled == "rocksdb::DBOptions::~DBOptions()")
        #expect(demangled != mangled)
    }

    @Test
    func demangleCppConstructor() {
        let mangled = "_ZN7rocksdb19ColumnFamilyOptionsC2ERKS0_"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled == "rocksdb::ColumnFamilyOptions::ColumnFamilyOptions(rocksdb::ColumnFamilyOptions const&)")
        #expect(demangled != mangled)
    }

    @Test
    func demangleCppStdFunction() {
        let mangled = "_ZNSt3__120__throw_length_errorB8ne180100EPKc"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled == "std::__1::__throw_length_error[abi:ne180100](char const*)")
        #expect(demangled != mangled)
    }

    @Test
    func demangleCppTemplateFunction() {
        let mangled = "_ZNSt3__119__allocate_at_leastB8ne180100INS_9allocatorIN7rocksdb13LevelMetaDataEEEEENS_19__allocation_resultINS_16allocator_traitsIT_E7pointerEEERS7_m"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled.contains("std::__1::__allocate_at_least"))
        #expect(demangled.contains("rocksdb::LevelMetaData"))
        #expect(demangled.contains("allocator"))
        #expect(demangled != mangled)
    }

    @Test
    func demangleCppComplexTemplate() {
        let mangled = "_ZNSt3__135__uninitialized_allocator_copy_implB8ne180100INS_9allocatorIN7rocksdb15SstFileMetaDataEEEPS3_S5_S5_EET2_RT_T0_T1_S6_"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled.contains("std::__1::__uninitialized_allocator_copy_impl"))
        #expect(demangled.contains("rocksdb::SstFileMetaData"))
        #expect(demangled != mangled)
    }

    @Test
    func demangleCppUnorderedMap() {
        let mangled = "_ZNSt3__113unordered_mapINS_12basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEES6_NS_4hashIS6_EENS_8equal_toIS6_EENS4_INS_4pairIKS6_S6_EEEEEC2ESt16initializer_listISD_E"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled.contains("std::__1::unordered_map"))
        #expect(demangled.contains("basic_string"))
        #expect(demangled.contains("initializer_list"))
        #expect(demangled != mangled)
    }

    @Test
    func demangleCppPairConstructor() {
        let mangled = "_ZNSt3__14pairIKNS_12basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEES6_EC2B8ne180100IRA36_KcRA2_SA_Li0EEEOT_OT0_"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled.contains("std::__1::pair"))
        #expect(demangled.contains("basic_string"))
        #expect(demangled.contains("pair[abi:ne180100]"))
        #expect(demangled != mangled)
    }

    // MARK: - Edge Cases

    @Test
    func demanglerHandlesNonMangledNames() {
        let plainName = "main"
        let demangled = Demangler.demangle(plainName)

        // Should return the original name unchanged
        #expect(demangled == plainName)
    }

    @Test
    func demanglerHandlesObjCNames() {
        let objcName = "-[NSObject description]"
        let demangled = Demangler.demangle(objcName)

        // Should return the original name unchanged
        #expect(demangled == objcName)
    }

    @Test
    func demanglerHandlesEmptyString() {
        let empty = ""
        let demangled = Demangler.demangle(empty)

        #expect(demangled == empty)
    }

    @Test
    func demanglerHandlesInvalidSwiftMangling() {
        // Starts with Swift prefix but is invalid
        let invalid = "$s_invalid_mangling"
        let demangled = Demangler.demangle(invalid)

        // Should return original if demangling fails
        #expect(demangled == invalid)
    }

    @Test
    func demanglerHandlesInvalidCppMangling() {
        // Starts with C++ prefix but is invalid
        let invalid = "_Z_invalid"
        let demangled = Demangler.demangle(invalid)

        // Should return original if demangling fails
        #expect(demangled == invalid)
    }

    // MARK: - Prefix Detection

    @Test
    func detectsSwiftManglingPrefixes() {
        let prefixes = ["$s", "$S", "_T", "_$s"]

        for prefix in prefixes {
            let mangled = prefix + "dummy"
            // The demangler should at least attempt Swift demangling
            // (will return original if invalid, but shows it was attempted)
            _ = Demangler.demangle(mangled)
        }
    }

    @Test
    func detectsCppManglingPrefix() {
        let mangled = "_Zdummy"
        // The demangler should attempt C++ demangling
        _ = Demangler.demangle(mangled)
    }

    // MARK: - Real-World Mixed Examples

    @Test
    func demangleRocksDBGetMethod() {
        // Real C++ method from RocksDB
        let mangled = "_ZN7rocksdb2DB3GetERKNS_11ReadOptionsEPNS_18ColumnFamilyHandleERKNS_5SliceEPNSt3__112basic_stringIcNS9_11char_traitsIcEENS9_9allocatorIcEEEE.cold.1"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled.contains("rocksdb::DB::Get"))
        #expect(demangled.contains("ReadOptions"))
        #expect(demangled.contains("ColumnFamilyHandle"))
        #expect(demangled != mangled)
    }

    @Test
    func demangleSwiftFunctionSignatureSpecialization() {
        let mangled = "$s13GoodNotesCore14RocksDBFactoryC9StoreTypeO15writeBufferSize33_F00D8FEB7571F81DD3186D0DB8BA7E4FLL14physicalMemorySis6UInt64V_tF"
        let demangled = Demangler.demangle(mangled)

        #expect(demangled.contains("GoodNotesCore.RocksDBFactory.StoreType"))
        #expect(demangled.contains("writeBufferSize"))
        #expect(demangled.contains("physicalMemory"))
        #expect(demangled != mangled)
    }
}
