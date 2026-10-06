#include <string.h>
#include <nettle/aes.h>
#include <nettle/cbc.h>

int
sdb_office_aes_decrypt (const unsigned char *key, int key_len, const unsigned char *iv, unsigned char *data, int len)
{
    struct aes128_ctx c128;
    struct aes192_ctx c192;
    struct aes256_ctx c256;
    void *ctx;
    nettle_cipher_func *fn;
    unsigned char chain[16];

    if (len <= 0 || len % 16 != 0)
        return -1;
    switch (key_len) {
    case 16:
        aes128_set_decrypt_key (&c128, key);
        ctx = &c128;
        fn = (nettle_cipher_func *) aes128_decrypt;
        break;
    case 24:
        aes192_set_decrypt_key (&c192, key);
        ctx = &c192;
        fn = (nettle_cipher_func *) aes192_decrypt;
        break;
    case 32:
        aes256_set_decrypt_key (&c256, key);
        ctx = &c256;
        fn = (nettle_cipher_func *) aes256_decrypt;
        break;
    default:
        return -1;
    }
    if (iv == NULL) {
        fn (ctx, (size_t) len, data, data);
    } else {
        memcpy (chain, iv, 16);
        cbc_decrypt (ctx, fn, 16, chain, (size_t) len, data, data);
    }
    memset (&c128, 0, sizeof c128);
    memset (&c192, 0, sizeof c192);
    memset (&c256, 0, sizeof c256);
    return 0;
}
