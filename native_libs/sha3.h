#ifndef SHA3_H
#define SHA3_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t state[25];
    uint32_t rate;
    uint32_t pt;
} SHA3_CTX;

void sha3_512_init(SHA3_CTX *ctx);
void sha3_512_update(SHA3_CTX *ctx, const uint8_t *data, size_t len);
void sha3_512_final(uint8_t *digest, SHA3_CTX *ctx);

#ifdef __cplusplus
}
#endif

#endif