import 'dart:ffi';
import 'package:ffi/ffi.dart';

// The C++ function signature: unsigned long coursedeep_hash(const char* s);
typedef HashNative = Uint64 Function(Pointer<Utf8>);
typedef HashDart = int Function(Pointer<Utf8>);

class NativeService {
  static final NativeService _instance = NativeService._internal();
  factory NativeService() => _instance;
  NativeService._internal();

  late final DynamicLibrary _lib;
  late final HashDart _hashFunc;
  bool _loaded = false;

  void init() {
    if (_loaded) return;
    try {
      // Load the .so file compiled from C++ in Termux
      _lib = DynamicLibrary.open('libcoursedeep.so');
      _hashFunc = _lib.lookupFunction<HashNative, HashDart>('coursedeep_hash');
      _loaded = true;
    } catch (_) {
      // Silently fail if running on a platform without the .so (like web)
    }
  }

  int getHash(String text) {
    if (!_loaded) return text.hashCode;
    
    // Convert Dart string to C-compatible UTF8 pointer
    final ptr = text.toNativeUtf8();
    try {
      return _hashFunc(ptr);
    } finally {
      calloc.free(ptr); // Prevent memory leaks
    }
  }
}
