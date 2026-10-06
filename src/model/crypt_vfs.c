#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <nettle/aes.h>
#include <nettle/ctr.h>
#include <nettle/hmac.h>
#include <nettle/pbkdf2.h>
#include <nettle/memops.h>

#define SDB_VFS_NAME "sdbcrypt"
#define SDB_MAGIC "SDBENC"
#define SDB_MAGIC_LEN 6
#define SDB_SALT_LEN 10
#define SDB_PREFIX 16
#define SDB_RESERVE 32
#define SDB_IV_LEN 16
#define SDB_TAG_LEN 16
#define SDB_ITERATIONS 256000
#define SDB_STREAM_PREFIX 16

typedef struct SdbKey SdbKey;

struct SdbKey {
    char *path;
    char *password;
    size_t password_len;
    int refs;
    int have_keys;
    unsigned char salt[SDB_SALT_LEN];
    unsigned char enc[32];
    unsigned char mac[32];
    SdbKey *next;
};

enum {
    SDB_PLAIN,
    SDB_PAGED,
    SDB_STREAM
};

typedef struct {
    sqlite3_file base;
    sqlite3_file *real;
    int mode;
    int page_size;
    int read_only;
    unsigned char salt[SDB_SALT_LEN];
    unsigned char mac[32];
    unsigned char nonce[16];
    struct aes256_ctx aes;
} SdbFile;

static const char SDB_SQLITE_HEADER[16] = "SQLite format 3";

static sqlite3_vfs sdb_vfs;
static sqlite3_vfs *sdb_base = NULL;
static SdbKey *sdb_keys = NULL;
static unsigned char sdb_temp_key[32];
static int sdb_temp_ready = 0;

static void
sdb_wipe (void *p, size_t n)
{
    volatile unsigned char *v = p;
    while (n--)
        *v++ = 0;
}

static sqlite3_mutex *
sdb_mutex (void)
{
    return sqlite3_mutex_alloc (SQLITE_MUTEX_STATIC_APP1);
}

static SdbKey *
sdb_find (const char *path)
{
    SdbKey *k;
    if (path == NULL)
        return NULL;
    for (k = sdb_keys; k != NULL; k = k->next) {
        if (strcmp (k->path, path) == 0)
            return k;
    }
    return NULL;
}

static void
sdb_derive (SdbKey *k, const unsigned char *salt)
{
    unsigned char out[64];
    if (k->have_keys && memcmp (k->salt, salt, SDB_SALT_LEN) == 0)
        return;
    pbkdf2_hmac_sha256 (k->password_len, (const uint8_t *) k->password, SDB_ITERATIONS, SDB_SALT_LEN, salt, sizeof out, out);
    memcpy (k->salt, salt, SDB_SALT_LEN);
    memcpy (k->enc, out, 32);
    memcpy (k->mac, out + 32, 32);
    k->have_keys = 1;
    sdb_wipe (out, sizeof out);
}

static void
sdb_put32 (unsigned char *p, sqlite3_uint64 v)
{
    p[0] = (unsigned char) (v >> 24);
    p[1] = (unsigned char) (v >> 16);
    p[2] = (unsigned char) (v >> 8);
    p[3] = (unsigned char) v;
}

static void
sdb_tag (SdbFile *p, sqlite3_int64 pgno, const unsigned char *iv, const unsigned char *data, int len, unsigned char *tag)
{
    struct hmac_sha256_ctx h;
    unsigned char num[4];
    unsigned char full[SHA256_DIGEST_SIZE];
    sdb_put32 (num, (sqlite3_uint64) pgno);
    hmac_sha256_set_key (&h, 32, p->mac);
    hmac_sha256_update (&h, 4, num);
    hmac_sha256_update (&h, SDB_IV_LEN, iv);
    hmac_sha256_update (&h, (size_t) len, data);
    hmac_sha256_digest (&h, sizeof full, full);
    memcpy (tag, full, SDB_TAG_LEN);
    sdb_wipe (&h, sizeof h);
}

static void
sdb_ctr (SdbFile *p, const unsigned char *iv, unsigned char *data, int len)
{
    unsigned char ctr[16];
    memcpy (ctr, iv, 16);
    ctr_crypt (&p->aes, (nettle_cipher_func *) aes256_encrypt, AES_BLOCK_SIZE, ctr, (size_t) len, data, data);
}

static void
sdb_stream (SdbFile *p, unsigned char *buf, int amt, sqlite3_int64 off)
{
    unsigned char block[16];
    unsigned char ks[16];
    sqlite3_uint64 index = (sqlite3_uint64) off / 16;
    int skip = (int) (off % 16);
    int i = 0;
    while (i < amt) {
        sqlite3_uint64 lo = 0;
        int k;
        memcpy (block, p->nonce, 16);
        for (k = 8; k < 16; k++)
            lo = (lo << 8) | block[k];
        lo += index;
        for (k = 15; k >= 8; k--) {
            block[k] = (unsigned char) lo;
            lo >>= 8;
        }
        aes256_encrypt (&p->aes, 16, ks, block);
        for (k = skip; k < 16 && i < amt; k++, i++)
            buf[i] ^= ks[k];
        skip = 0;
        index++;
    }
    sdb_wipe (ks, sizeof ks);
}

static int
sdb_valid_page_size (int n)
{
    return n >= 512 && n <= 65536 && (n & (n - 1)) == 0;
}

static int
sdb_page_read (SdbFile *p, sqlite3_int64 index, unsigned char *out)
{
    int ps = p->page_size;
    int start = index == 0 ? SDB_PREFIX : 0;
    int end = ps - SDB_RESERVE;
    unsigned char tag[SDB_TAG_LEN];
    unsigned char *raw = sqlite3_malloc (ps);
    int rc;
    if (raw == NULL)
        return SQLITE_NOMEM;
    rc = p->real->pMethods->xRead (p->real, raw, ps, index * ps);
    if (rc == SQLITE_IOERR_SHORT_READ) {
        memset (out, 0, ps);
        sqlite3_free (raw);
        return SQLITE_IOERR_SHORT_READ;
    }
    if (rc != SQLITE_OK) {
        sqlite3_free (raw);
        return rc;
    }
    sdb_tag (p, index + 1, raw + end, raw + start, end - start, tag);
    if (!memeql_sec (tag, raw + end + SDB_IV_LEN, SDB_TAG_LEN)) {
        sqlite3_free (raw);
        return index == 0 ? SQLITE_NOTADB : SQLITE_IOERR_DATA;
    }
    sdb_ctr (p, raw + end, raw + start, end - start);
    memcpy (out, raw, ps);
    if (index == 0)
        memcpy (out, SDB_SQLITE_HEADER, SDB_PREFIX);
    memset (out + end, 0, SDB_RESERVE);
    sdb_wipe (raw, ps);
    sqlite3_free (raw);
    return SQLITE_OK;
}

static int
sdb_page_write (SdbFile *p, sqlite3_int64 index, const unsigned char *in)
{
    int ps = p->page_size;
    int start = index == 0 ? SDB_PREFIX : 0;
    int end = ps - SDB_RESERVE;
    unsigned char *raw = sqlite3_malloc (ps);
    int rc;
    if (raw == NULL)
        return SQLITE_NOMEM;
    memcpy (raw, in, ps);
    if (index == 0) {
        memcpy (raw, SDB_MAGIC, SDB_MAGIC_LEN);
        memcpy (raw + SDB_MAGIC_LEN, p->salt, SDB_SALT_LEN);
    }
    sqlite3_randomness (SDB_IV_LEN, raw + end);
    sdb_ctr (p, raw + end, raw + start, end - start);
    sdb_tag (p, index + 1, raw + end, raw + start, end - start, raw + end + SDB_IV_LEN);
    rc = p->real->pMethods->xWrite (p->real, raw, ps, index * ps);
    sqlite3_free (raw);
    return rc;
}

static int
sdb_detect (SdbFile *p)
{
    sqlite3_int64 size = 0;
    int rc;
    int ps;
    unsigned char *probe;
    if (p->page_size > 0)
        return SQLITE_OK;
    rc = p->real->pMethods->xFileSize (p->real, &size);
    if (rc != SQLITE_OK)
        return rc;
    if (size == 0)
        return SQLITE_OK;
    probe = sqlite3_malloc (65536);
    if (probe == NULL)
        return SQLITE_NOMEM;
    for (ps = 512; ps <= 65536; ps *= 2) {
        if (size < ps || size % ps != 0)
            continue;
        p->page_size = ps;
        rc = sdb_page_read (p, 0, probe);
        if (rc == SQLITE_OK) {
            sdb_wipe (probe, ps);
            sqlite3_free (probe);
            return SQLITE_OK;
        }
        p->page_size = 0;
    }
    sqlite3_free (probe);
    return SQLITE_NOTADB;
}

static int
sdb_close (sqlite3_file *f)
{
    SdbFile *p = (SdbFile *) f;
    int rc = SQLITE_OK;
    if (p->real->pMethods != NULL)
        rc = p->real->pMethods->xClose (p->real);
    sdb_wipe (&p->aes, sizeof p->aes);
    sdb_wipe (p->mac, sizeof p->mac);
    return rc;
}

static int
sdb_read (sqlite3_file *f, void *buf, int amt, sqlite3_int64 off)
{
    SdbFile *p = (SdbFile *) f;
    unsigned char *out = buf;
    int rc;
    if (p->mode == SDB_STREAM) {
        sqlite3_int64 size = 0;
        rc = p->real->pMethods->xRead (p->real, buf, amt, off + SDB_STREAM_PREFIX);
        if (rc == SQLITE_OK) {
            sdb_stream (p, out, amt, off);
        } else if (rc == SQLITE_IOERR_SHORT_READ) {
            sqlite3_int64 avail;
            p->real->pMethods->xFileSize (p->real, &size);
            avail = size - SDB_STREAM_PREFIX - off;
            if (avail < 0)
                avail = 0;
            if (avail > amt)
                avail = amt;
            sdb_stream (p, out, (int) avail, off);
            memset (out + avail, 0, amt - avail);
        }
        return rc;
    }
    if (p->mode != SDB_PAGED)
        return p->real->pMethods->xRead (p->real, buf, amt, off);
    rc = sdb_detect (p);
    if (rc != SQLITE_OK)
        return rc;
    if (p->page_size == 0) {
        memset (buf, 0, amt);
        return SQLITE_IOERR_SHORT_READ;
    }
    {
        int ps = p->page_size;
        sqlite3_int64 first = off / ps;
        sqlite3_int64 last = (off + amt - 1) / ps;
        sqlite3_int64 idx;
        int shorted = 0;
        unsigned char *page;
        if (off % ps == 0 && amt == ps)
            return sdb_page_read (p, first, out);
        page = sqlite3_malloc (ps);
        if (page == NULL)
            return SQLITE_NOMEM;
        for (idx = first; idx <= last; idx++) {
            sqlite3_int64 pstart = idx * ps;
            sqlite3_int64 a = off > pstart ? off : pstart;
            sqlite3_int64 b = (off + amt) < (pstart + ps) ? (off + amt) : (pstart + ps);
            rc = sdb_page_read (p, idx, page);
            if (rc == SQLITE_IOERR_SHORT_READ)
                shorted = 1;
            else if (rc != SQLITE_OK) {
                sqlite3_free (page);
                return rc;
            }
            memcpy (out + (a - off), page + (a - pstart), (size_t) (b - a));
        }
        sdb_wipe (page, ps);
        sqlite3_free (page);
        return shorted ? SQLITE_IOERR_SHORT_READ : SQLITE_OK;
    }
}

static int
sdb_write (sqlite3_file *f, const void *buf, int amt, sqlite3_int64 off)
{
    SdbFile *p = (SdbFile *) f;
    const unsigned char *in = buf;
    int rc;
    if (p->mode == SDB_STREAM) {
        unsigned char *tmp = sqlite3_malloc (amt);
        if (tmp == NULL)
            return SQLITE_NOMEM;
        memcpy (tmp, buf, amt);
        sdb_stream (p, tmp, amt, off);
        rc = p->real->pMethods->xWrite (p->real, tmp, amt, off + SDB_STREAM_PREFIX);
        sdb_wipe (tmp, amt);
        sqlite3_free (tmp);
        return rc;
    }
    if (p->mode != SDB_PAGED)
        return p->real->pMethods->xWrite (p->real, buf, amt, off);
    if (off == 0 && sdb_valid_page_size (amt) && amt != p->page_size)
        p->page_size = amt;
    if (p->page_size == 0) {
        rc = sdb_detect (p);
        if (rc != SQLITE_OK)
            return rc;
        if (p->page_size == 0)
            return SQLITE_IOERR_WRITE;
    }
    {
        int ps = p->page_size;
        sqlite3_int64 first = off / ps;
        sqlite3_int64 last = (off + amt - 1) / ps;
        sqlite3_int64 idx;
        unsigned char *page;
        if (off % ps == 0 && amt == ps)
            return sdb_page_write (p, first, in);
        page = sqlite3_malloc (ps);
        if (page == NULL)
            return SQLITE_NOMEM;
        for (idx = first; idx <= last; idx++) {
            sqlite3_int64 pstart = idx * ps;
            sqlite3_int64 a = off > pstart ? off : pstart;
            sqlite3_int64 b = (off + amt) < (pstart + ps) ? (off + amt) : (pstart + ps);
            rc = sdb_page_read (p, idx, page);
            if (rc != SQLITE_OK && rc != SQLITE_IOERR_SHORT_READ) {
                sqlite3_free (page);
                return rc;
            }
            memcpy (page + (a - pstart), in + (a - off), (size_t) (b - a));
            rc = sdb_page_write (p, idx, page);
            if (rc != SQLITE_OK) {
                sqlite3_free (page);
                return rc;
            }
        }
        sdb_wipe (page, ps);
        sqlite3_free (page);
        return SQLITE_OK;
    }
}

static int
sdb_new_nonce (SdbFile *p)
{
    sqlite3_randomness (16, p->nonce);
    if (p->read_only)
        return SQLITE_OK;
    return p->real->pMethods->xWrite (p->real, p->nonce, SDB_STREAM_PREFIX, 0);
}

static int
sdb_truncate (sqlite3_file *f, sqlite3_int64 size)
{
    SdbFile *p = (SdbFile *) f;
    if (p->mode == SDB_STREAM) {
        int rc = p->real->pMethods->xTruncate (p->real, size + SDB_STREAM_PREFIX);
        if (rc == SQLITE_OK && size == 0)
            rc = sdb_new_nonce (p);
        return rc;
    }
    return p->real->pMethods->xTruncate (p->real, size);
}

static int
sdb_sync (sqlite3_file *f, int flags)
{
    SdbFile *p = (SdbFile *) f;
    return p->real->pMethods->xSync (p->real, flags);
}

static int
sdb_file_size (sqlite3_file *f, sqlite3_int64 *size)
{
    SdbFile *p = (SdbFile *) f;
    int rc = p->real->pMethods->xFileSize (p->real, size);
    if (rc == SQLITE_OK && p->mode == SDB_STREAM) {
        *size -= SDB_STREAM_PREFIX;
        if (*size < 0)
            *size = 0;
    }
    return rc;
}

static int
sdb_lock (sqlite3_file *f, int level)
{
    SdbFile *p = (SdbFile *) f;
    return p->real->pMethods->xLock (p->real, level);
}

static int
sdb_unlock (sqlite3_file *f, int level)
{
    SdbFile *p = (SdbFile *) f;
    return p->real->pMethods->xUnlock (p->real, level);
}

static int
sdb_check_reserved (sqlite3_file *f, int *out)
{
    SdbFile *p = (SdbFile *) f;
    return p->real->pMethods->xCheckReservedLock (p->real, out);
}

static int
sdb_file_control (sqlite3_file *f, int op, void *arg)
{
    SdbFile *p = (SdbFile *) f;
    if (op == SQLITE_FCNTL_VFSNAME && p->mode != SDB_PLAIN) {
        *(char **) arg = sqlite3_mprintf ("%s", SDB_VFS_NAME);
        return SQLITE_OK;
    }
    return p->real->pMethods->xFileControl (p->real, op, arg);
}

static int
sdb_sector_size (sqlite3_file *f)
{
    SdbFile *p = (SdbFile *) f;
    return p->real->pMethods->xSectorSize (p->real);
}

static int
sdb_device (sqlite3_file *f)
{
    SdbFile *p = (SdbFile *) f;
    int c = p->real->pMethods->xDeviceCharacteristics (p->real);
    if (p->mode != SDB_PLAIN)
        c &= ~(SQLITE_IOCAP_ATOMIC | SQLITE_IOCAP_ATOMIC512 | SQLITE_IOCAP_ATOMIC1K | SQLITE_IOCAP_ATOMIC2K | SQLITE_IOCAP_ATOMIC4K | SQLITE_IOCAP_ATOMIC8K | SQLITE_IOCAP_ATOMIC16K | SQLITE_IOCAP_ATOMIC32K | SQLITE_IOCAP_ATOMIC64K | SQLITE_IOCAP_BATCH_ATOMIC);
    return c;
}

static int
sdb_shm_map (sqlite3_file *f, int pg, int sz, int extend, void volatile **out)
{
    SdbFile *p = (SdbFile *) f;
    return p->real->pMethods->xShmMap (p->real, pg, sz, extend, out);
}

static int
sdb_shm_lock (sqlite3_file *f, int offset, int n, int flags)
{
    SdbFile *p = (SdbFile *) f;
    return p->real->pMethods->xShmLock (p->real, offset, n, flags);
}

static void
sdb_shm_barrier (sqlite3_file *f)
{
    SdbFile *p = (SdbFile *) f;
    p->real->pMethods->xShmBarrier (p->real);
}

static int
sdb_shm_unmap (sqlite3_file *f, int del)
{
    SdbFile *p = (SdbFile *) f;
    return p->real->pMethods->xShmUnmap (p->real, del);
}

static int
sdb_fetch (sqlite3_file *f, sqlite3_int64 off, int amt, void **out)
{
    SdbFile *p = (SdbFile *) f;
    return p->real->pMethods->xFetch (p->real, off, amt, out);
}

static int
sdb_unfetch (sqlite3_file *f, sqlite3_int64 off, void *ptr)
{
    SdbFile *p = (SdbFile *) f;
    return p->real->pMethods->xUnfetch (p->real, off, ptr);
}

static const sqlite3_io_methods sdb_crypt_methods = {
    1,
    sdb_close,
    sdb_read,
    sdb_write,
    sdb_truncate,
    sdb_sync,
    sdb_file_size,
    sdb_lock,
    sdb_unlock,
    sdb_check_reserved,
    sdb_file_control,
    sdb_sector_size,
    sdb_device,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
};

static sqlite3_io_methods sdb_plain_methods;

static int
sdb_open_paged (SdbFile *p, SdbKey *k, int flags)
{
    sqlite3_int64 size = 0;
    unsigned char head[SDB_PREFIX];
    int rc = p->real->pMethods->xFileSize (p->real, &size);
    if (rc != SQLITE_OK)
        return rc;
    if (size == 0) {
        if (k->have_keys)
            memcpy (p->salt, k->salt, SDB_SALT_LEN);
        else
            sqlite3_randomness (SDB_SALT_LEN, p->salt);
    } else {
        if (size < SDB_PREFIX)
            return SQLITE_NOTADB;
        rc = p->real->pMethods->xRead (p->real, head, SDB_PREFIX, 0);
        if (rc != SQLITE_OK)
            return rc;
        if (memcmp (head, SDB_MAGIC, SDB_MAGIC_LEN) != 0)
            return SQLITE_NOTADB;
        memcpy (p->salt, head + SDB_MAGIC_LEN, SDB_SALT_LEN);
    }
    sdb_derive (k, p->salt);
    aes256_set_encrypt_key (&p->aes, k->enc);
    memcpy (p->mac, k->mac, 32);
    p->mode = SDB_PAGED;
    return SQLITE_OK;
}

static int
sdb_open_stream (SdbFile *p, const unsigned char *key)
{
    sqlite3_int64 size = 0;
    int rc = p->real->pMethods->xFileSize (p->real, &size);
    if (rc != SQLITE_OK)
        return rc;
    aes256_set_encrypt_key (&p->aes, key);
    p->mode = SDB_STREAM;
    if (size >= SDB_STREAM_PREFIX)
        return p->real->pMethods->xRead (p->real, p->nonce, SDB_STREAM_PREFIX, 0);
    if (size > 0 && !p->read_only)
        p->real->pMethods->xTruncate (p->real, 0);
    return sdb_new_nonce (p);
}

static SdbKey *
sdb_find_owner (const char *name)
{
    static const char *suffixes[] = { "-journal", "-wal", NULL };
    size_t n;
    int i;
    if (name == NULL)
        return NULL;
    n = strlen (name);
    for (i = 0; suffixes[i] != NULL; i++) {
        size_t s = strlen (suffixes[i]);
        if (n > s && strcmp (name + n - s, suffixes[i]) == 0) {
            char *base = sqlite3_mprintf ("%.*s", (int) (n - s), name);
            SdbKey *k = sdb_find (base);
            sqlite3_free (base);
            return k;
        }
    }
    return NULL;
}

static int
sdb_open (sqlite3_vfs *vfs, sqlite3_filename name, sqlite3_file *f, int flags, int *out_flags)
{
    SdbFile *p = (SdbFile *) f;
    sqlite3_mutex *m = sdb_mutex ();
    int rc;
    memset (p, 0, sizeof (SdbFile));
    p->real = (sqlite3_file *) &p[1];
    rc = sdb_base->xOpen (sdb_base, name, p->real, flags, out_flags);
    if (rc != SQLITE_OK) {
        f->pMethods = NULL;
        return rc;
    }
    p->read_only = (flags & SQLITE_OPEN_READONLY) != 0;
    sqlite3_mutex_enter (m);
    if (flags & SQLITE_OPEN_MAIN_DB) {
        SdbKey *k = sdb_find (name);
        if (k != NULL)
            rc = sdb_open_paged (p, k, flags);
    } else if (flags & (SQLITE_OPEN_MAIN_JOURNAL | SQLITE_OPEN_WAL)) {
        SdbKey *k = sdb_find_owner (name);
        if (k != NULL) {
            if (!k->have_keys)
                rc = SQLITE_CANTOPEN;
            else
                rc = sdb_open_stream (p, k->enc);
        }
    } else if (flags & (SQLITE_OPEN_TEMP_DB | SQLITE_OPEN_TEMP_JOURNAL | SQLITE_OPEN_SUBJOURNAL | SQLITE_OPEN_TRANSIENT_DB)) {
        if (!sdb_temp_ready) {
            sqlite3_randomness (32, sdb_temp_key);
            sdb_temp_ready = 1;
        }
        rc = sdb_open_stream (p, sdb_temp_key);
    }
    sqlite3_mutex_leave (m);
    if (rc != SQLITE_OK) {
        p->real->pMethods->xClose (p->real);
        f->pMethods = NULL;
        return rc;
    }
    f->pMethods = p->mode == SDB_PLAIN ? &sdb_plain_methods : &sdb_crypt_methods;
    return SQLITE_OK;
}

static int
sdb_delete (sqlite3_vfs *vfs, const char *name, int sync)
{
    return sdb_base->xDelete (sdb_base, name, sync);
}

static int
sdb_access (sqlite3_vfs *vfs, const char *name, int flags, int *out)
{
    return sdb_base->xAccess (sdb_base, name, flags, out);
}

static int
sdb_full_path (sqlite3_vfs *vfs, const char *name, int n, char *out)
{
    return sdb_base->xFullPathname (sdb_base, name, n, out);
}

static void *
sdb_dl_open (sqlite3_vfs *vfs, const char *name)
{
    return sdb_base->xDlOpen (sdb_base, name);
}

static void
sdb_dl_error (sqlite3_vfs *vfs, int n, char *msg)
{
    sdb_base->xDlError (sdb_base, n, msg);
}

static void (*sdb_dl_sym (sqlite3_vfs *vfs, void *h, const char *sym)) (void)
{
    return sdb_base->xDlSym (sdb_base, h, sym);
}

static void
sdb_dl_close (sqlite3_vfs *vfs, void *h)
{
    sdb_base->xDlClose (sdb_base, h);
}

static int
sdb_randomness (sqlite3_vfs *vfs, int n, char *out)
{
    return sdb_base->xRandomness (sdb_base, n, out);
}

static int
sdb_sleep (sqlite3_vfs *vfs, int us)
{
    return sdb_base->xSleep (sdb_base, us);
}

static int
sdb_current_time (sqlite3_vfs *vfs, double *out)
{
    return sdb_base->xCurrentTime (sdb_base, out);
}

static int
sdb_last_error (sqlite3_vfs *vfs, int n, char *out)
{
    return sdb_base->xGetLastError ? sdb_base->xGetLastError (sdb_base, n, out) : 0;
}

static int
sdb_current_time64 (sqlite3_vfs *vfs, sqlite3_int64 *out)
{
    return sdb_base->xCurrentTimeInt64 (sdb_base, out);
}

int
sdb_crypt_register (void)
{
    sqlite3_mutex *m;
    int rc = SQLITE_OK;
    sqlite3_initialize ();
    m = sdb_mutex ();
    sqlite3_mutex_enter (m);
    if (sdb_base == NULL) {
        sdb_base = sqlite3_vfs_find (NULL);
        if (sdb_base == NULL) {
            sqlite3_mutex_leave (m);
            return SQLITE_ERROR;
        }
        memset (&sdb_vfs, 0, sizeof sdb_vfs);
        sdb_vfs.iVersion = 2;
        sdb_vfs.szOsFile = (int) sizeof (SdbFile) + sdb_base->szOsFile;
        sdb_vfs.mxPathname = sdb_base->mxPathname;
        sdb_vfs.zName = SDB_VFS_NAME;
        sdb_vfs.xOpen = sdb_open;
        sdb_vfs.xDelete = sdb_delete;
        sdb_vfs.xAccess = sdb_access;
        sdb_vfs.xFullPathname = sdb_full_path;
        sdb_vfs.xDlOpen = sdb_dl_open;
        sdb_vfs.xDlError = sdb_dl_error;
        sdb_vfs.xDlSym = sdb_dl_sym;
        sdb_vfs.xDlClose = sdb_dl_close;
        sdb_vfs.xRandomness = sdb_randomness;
        sdb_vfs.xSleep = sdb_sleep;
        sdb_vfs.xCurrentTime = sdb_current_time;
        sdb_vfs.xGetLastError = sdb_last_error;
        sdb_vfs.xCurrentTimeInt64 = sdb_current_time64;
        sdb_plain_methods = sdb_crypt_methods;
        sdb_plain_methods.iVersion = 3;
        sdb_plain_methods.xShmMap = sdb_shm_map;
        sdb_plain_methods.xShmLock = sdb_shm_lock;
        sdb_plain_methods.xShmBarrier = sdb_shm_barrier;
        sdb_plain_methods.xShmUnmap = sdb_shm_unmap;
        sdb_plain_methods.xFetch = sdb_fetch;
        sdb_plain_methods.xUnfetch = sdb_unfetch;
        rc = sqlite3_vfs_register (&sdb_vfs, 0);
    }
    sqlite3_mutex_leave (m);
    return rc;
}

static char *
sdb_full (const char *path)
{
    int n;
    char *out;
    if (sdb_base == NULL)
        return NULL;
    n = sdb_base->mxPathname + 1;
    out = sqlite3_malloc (n);
    if (out == NULL)
        return NULL;
    if (sdb_base->xFullPathname (sdb_base, path, n, out) != SQLITE_OK) {
        sqlite3_free (out);
        return sqlite3_mprintf ("%s", path);
    }
    return out;
}

int
sdb_crypt_set_key (const char *path, const char *password)
{
    sqlite3_mutex *m;
    SdbKey *k;
    char *full;
    size_t len;
    if (path == NULL || password == NULL)
        return SQLITE_MISUSE;
    if (sdb_crypt_register () != SQLITE_OK)
        return SQLITE_ERROR;
    full = sdb_full (path);
    if (full == NULL)
        return SQLITE_NOMEM;
    len = strlen (password);
    m = sdb_mutex ();
    sqlite3_mutex_enter (m);
    k = sdb_find (full);
    if (k != NULL && (k->password_len != len || memcmp (k->password, password, len) != 0)) {
        sdb_wipe (k->password, k->password_len);
        sqlite3_free (k->password);
        k->password = sqlite3_malloc ((int) len + 1);
        memcpy (k->password, password, len + 1);
        k->password_len = len;
        k->have_keys = 0;
        sdb_wipe (k->enc, sizeof k->enc);
        sdb_wipe (k->mac, sizeof k->mac);
    }
    if (k != NULL) {
        k->refs++;
        sqlite3_free (full);
        sqlite3_mutex_leave (m);
        return SQLITE_OK;
    }
    k = sqlite3_malloc (sizeof (SdbKey));
    if (k == NULL) {
        sqlite3_free (full);
        sqlite3_mutex_leave (m);
        return SQLITE_NOMEM;
    }
    memset (k, 0, sizeof (SdbKey));
    k->path = full;
    k->password = sqlite3_malloc ((int) len + 1);
    memcpy (k->password, password, len + 1);
    k->password_len = len;
    k->refs = 1;
    k->next = sdb_keys;
    sdb_keys = k;
    sqlite3_mutex_leave (m);
    return SQLITE_OK;
}

void
sdb_crypt_clear_key (const char *path)
{
    sqlite3_mutex *m;
    SdbKey **pp;
    char *full;
    if (path == NULL || sdb_base == NULL)
        return;
    full = sdb_full (path);
    if (full == NULL)
        return;
    m = sdb_mutex ();
    sqlite3_mutex_enter (m);
    for (pp = &sdb_keys; *pp != NULL; pp = &(*pp)->next) {
        SdbKey *k = *pp;
        if (strcmp (k->path, full) != 0)
            continue;
        if (--k->refs > 0)
            break;
        *pp = k->next;
        sdb_wipe (k->password, k->password_len);
        sdb_wipe (k->enc, sizeof k->enc);
        sdb_wipe (k->mac, sizeof k->mac);
        sqlite3_free (k->password);
        sqlite3_free (k->path);
        sqlite3_free (k);
        break;
    }
    sqlite3_mutex_leave (m);
    sqlite3_free (full);
}

int
sdb_crypt_is_encrypted (const char *path)
{
    unsigned char head[SDB_MAGIC_LEN];
    FILE *f;
    size_t n;
    if (path == NULL)
        return 0;
    f = fopen (path, "rb");
    if (f == NULL)
        return 0;
    n = fread (head, 1, SDB_MAGIC_LEN, f);
    fclose (f);
    return n == SDB_MAGIC_LEN && memcmp (head, SDB_MAGIC, SDB_MAGIC_LEN) == 0;
}

int
sdb_crypt_set_reserve (sqlite3 *db, int n)
{
    return sqlite3_file_control (db, "main", SQLITE_FCNTL_RESERVE_BYTES, &n);
}

int
sdb_crypt_available (void)
{
    return 1;
}
