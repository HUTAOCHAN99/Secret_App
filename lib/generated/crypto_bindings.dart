// lib/generated/crypto_bindings.dart
import 'dart:ffi';
import 'package:ffi/ffi.dart';

final class SHA3_CTX extends Struct {
  @Array(25)
  external Array<Uint64> state;
  
  @Uint32()
  external int rate;
  
  @Uint32()
  external int pt;
}

class CryptoBindings {
  final DynamicLibrary lib;

  CryptoBindings(this.lib) {
    _initializeFunctions();
  }

  late final int Function(
    int tCost,
    int mCost, 
    int parallelism,
    Pointer<Uint8> pwd,
    int pwdlen,
    Pointer<Uint8> salt,
    int saltlen,
    Pointer<Uint8> hash,
    int hashlen,
  ) argon2id_hash_raw;


  late final void Function(Pointer<SHA3_CTX> ctx) sha3_512_init;
  late final void Function(Pointer<SHA3_CTX> ctx, Pointer<Uint8> data, int len) sha3_512_update;
  late final void Function(Pointer<Uint8> digest, Pointer<SHA3_CTX> ctx) sha3_512_final;

  void _initializeFunctions() {
    try {
      final argon2Lookup = lib.lookup<NativeFunction<
        Int32 Function(
          Uint32, Uint32, Uint32,
          Pointer<Uint8>, IntPtr,
          Pointer<Uint8>, IntPtr,
          Pointer<Uint8>, IntPtr
        )
      >>('argon2id_hash_raw');
      
      argon2id_hash_raw = argon2Lookup.asFunction();

      final sha3InitLookup = lib.lookup<NativeFunction<
        Void Function(Pointer<SHA3_CTX>)
      >>('sha3_512_init');
      sha3_512_init = sha3InitLookup.asFunction();

      final sha3UpdateLookup = lib.lookup<NativeFunction<
        Void Function(Pointer<SHA3_CTX>, Pointer<Uint8>, IntPtr)
      >>('sha3_512_update');
      sha3_512_update = sha3UpdateLookup.asFunction();

      final sha3FinalLookup = lib.lookup<NativeFunction<
        Void Function(Pointer<Uint8>, Pointer<SHA3_CTX>)
      >>('sha3_512_final');
      sha3_512_final = sha3FinalLookup.asFunction();

      print('✅ All native functions loaded successfully');
    } catch (e) {
      print('❌ Error loading native functions: $e');
      rethrow;
    }
  }

  bool testBindings() {
    try {
      final ctx = calloc<SHA3_CTX>();
      sha3_512_init(ctx);
      calloc.free(ctx);
      
      return true;
    } catch (e) {
      print('Binding test failed: $e');
      return false;
    }
  }
}