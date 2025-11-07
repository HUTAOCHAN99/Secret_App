// lib/generated/crypto_bindings.dart
// MANUAL BINDING - NO FFIGEN NEEDED

import 'dart:ffi';
import 'package:ffi/ffi.dart';

/// SHA3 Context Structure - harus base/final
final class SHA3_CTX extends Struct {
  @Array(25)
  external Array<Uint64> state;
  
  @Uint32()
  external int rate;
  
  @Uint32()
  external int pt;
}

/// Crypto Bindings for Argon2 and SHA3
class CryptoBindings {
  final DynamicLibrary lib;

  CryptoBindings(this.lib) {
    _initializeFunctions();
  }

  // === ARGON2 FUNCTIONS ===
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

  // === SHA3 FUNCTIONS ===
  late final void Function(Pointer<SHA3_CTX> ctx) sha3_512_init;
  late final void Function(Pointer<SHA3_CTX> ctx, Pointer<Uint8> data, int len) sha3_512_update;
  late final void Function(Pointer<Uint8> digest, Pointer<SHA3_CTX> ctx) sha3_512_final;

  void _initializeFunctions() {
    try {
      // === Initialize Argon2 ===
      final argon2Lookup = lib.lookup<NativeFunction<
        Int32 Function(
          Uint32, Uint32, Uint32,
          Pointer<Uint8>, IntPtr,
          Pointer<Uint8>, IntPtr,
          Pointer<Uint8>, IntPtr
        )
      >>('argon2id_hash_raw');
      
      argon2id_hash_raw = argon2Lookup.asFunction();

      // === Initialize SHA3 ===
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

  /// Test function to verify bindings work
  bool testBindings() {
    try {
      // Test SHA3 initialization
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