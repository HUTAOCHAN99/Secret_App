#ifndef ARGON2_H
#define ARGON2_H

#include <stdint.h>
#include <stddef.h>

#if defined(__cplusplus)
extern "C" {
#endif

// Hanya export function yang kita butuhkan
__declspec(dllimport) int argon2id_hash_raw(uint32_t t_cost, uint32_t m_cost, uint32_t parallelism,
                                           const void *pwd, size_t pwdlen,
                                           const void *salt, size_t saltlen, 
                                           void *hash, size_t hashlen);

#if defined(__cplusplus)
}
#endif

#endif