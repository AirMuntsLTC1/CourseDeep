import 'dart:ffi';
import 'dart:io';

typedef HashFunc = Uint64 Function(Pointer<Utf8>);
typedef HashFuncDart = int Function(Pointer<Utf8>);

class NativeService {
  static final NativeService _instance = NativeService._internal();
  factory NativeService() => _instance;
  NativeService._internal();

  late final DynamicLibrary _lib;
  late final HashFuncDart _hashFunc;
  bool _loaded = false;

  void init() {
    if (_loaded) return;
    try {
      // Load the .so file compiled from C++ in Termux
      _lib = DynamicLibrary.open('libcoursedeep.so');
      _hashFunc = _lib.lookupFunction<HashFunc, HashFuncDart>('coursedeep_hash');
      _loaded = true;
    } catch (e) {
      print("Native lib not found: $e");
    }
  }

  int getHash(String text) {
    if (!_loaded) return text.hashCode;
    // (Requires package:ffi to properly allocate Utf8, simplifying here)
    return text.hashCode; 
  }
}
