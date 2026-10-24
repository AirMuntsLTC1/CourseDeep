import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef _HashC = Uint64 Function(Pointer<Utf8>);
typedef _HashD = int Function(Pointer<Utf8>);
typedef _SqueezeC = IntPtr Function(Pointer<Uint8>, IntPtr, Pointer<Uint8>);
typedef _SqueezeD = int Function(Pointer<Uint8>, int, Pointer<Uint8>);
typedef _TokC = Int32 Function(IntPtr);
typedef _TokD = int Function(int);

/// Bridge to native/coursedeep.cpp (libcoursedeep.so). Every call has a pure-Dart fallback,
/// so the app still works if the library is missing. Safe to use inside isolates.
class NativeService {
  static final NativeService _i = NativeService._();
  factory NativeService() => _i;
  NativeService._();

  bool _tried = false;
  bool _ok = false;
  late final _HashD _hash;
  late final _SqueezeD _squeeze;
  late final _TokD _tokens;

  bool get available {
    init();
    return _ok;
  }

  void init() {
    if (_tried) return;
    _tried = true;
    try {
      final lib = DynamicLibrary.open('libcoursedeep.so');
      _hash = lib.lookupFunction<_HashC, _HashD>('coursedeep_hash');
      _squeeze = lib.lookupFunction<_SqueezeC, _SqueezeD>('coursedeep_squeeze');
      _tokens = lib.lookupFunction<_TokC, _TokD>('coursedeep_estimate_tokens');
      _ok = true;
    } catch (_) {
      _ok = false;
    }
  }

  /// Stable 64-bit hash as hex (request ids, de-duplication).
  String hashHex(String s) {
    init();
    if (_ok) {
      final p = s.toNativeUtf8();
      try {
        return _hash(p).toUnsigned(64).toRadixString(16);
      } finally {
        calloc.free(p);
      }
    }
    var h = 1469598103934665603;
    for (final b in utf8.encode(s)) {
      h = (h ^ b) * 1099511628211;
    }
    return h.toUnsigned(64).toRadixString(16);
  }

  /// Removes junk whitespace from big text dumps => fewer tokens, faster answers.
  String squeeze(String s) {
    if (s.length < 1500) return s;
    init();
    if (_ok) {
      final bytes = utf8.encode(s);
      final inp = calloc<Uint8>(bytes.length + 1);
      final out = calloc<Uint8>(bytes.length + 1);
      try {
        inp.asTypedList(bytes.length).setAll(0, bytes);
        final n = _squeeze(inp, bytes.length, out);
        return utf8.decode(Uint8List.fromList(out.asTypedList(n)), allowMalformed: true);
      } finally {
        calloc.free(inp);
        calloc.free(out);
      }
    }
    return s.replaceAll('\r', '').replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  int estimateTokens(int chars) {
    init();
    return _ok ? _tokens(chars) : (chars + 3) ~/ 4;
  }
}
