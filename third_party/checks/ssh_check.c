/* Link/run check for libssh2 + OpenSSL. Same source for ios-armv7 (link only) and macos-arm64 (run). */
#include <stdio.h>
#include <string.h>
#include <libssh2.h>
#include <openssl/crypto.h>
#include <openssl/rand.h>
#include <openssl/evp.h>

static int list(LIBSSH2_SESSION *s, int method, const char *name, const char *must[], int nmust) {
    const char **algs = NULL;
    int n = libssh2_session_supported_algs(s, method, &algs);
    if (n < 0) { printf("%s: error %d\n", name, n); return 1; }
    printf("%s (%d):", name, n);
    for (int i = 0; i < n; i++) printf(" %s", algs[i]);
    printf("\n");
    int bad = 0;
    for (int m = 0; m < nmust; m++) {
        int ok = 0;
        for (int i = 0; i < n; i++) if (!strcmp(algs[i], must[m])) ok = 1;
        printf("  %s %s: %s\n", name, must[m], ok ? "PRESENT" : "MISSING");
        bad |= !ok;
    }
    return bad;
}

int main(void) {
    int rc = libssh2_init(0);
    printf("libssh2_init rc=%d\n", rc);
    printf("libssh2 %s\n", libssh2_version(0));
    printf("%s\n", OpenSSL_version(OPENSSL_VERSION));
    unsigned char r[32];
    printf("RAND_bytes rc=%d\n", RAND_bytes(r, sizeof r));
    EVP_PKEY_CTX *c = EVP_PKEY_CTX_new_id(EVP_PKEY_ED25519, NULL);
    EVP_PKEY *k = NULL;
    printf("ed25519 keygen: %s\n", (c && EVP_PKEY_keygen_init(c) == 1 && EVP_PKEY_keygen(c, &k) == 1) ? "ok" : "FAIL");
    EVP_PKEY_free(k); EVP_PKEY_CTX_free(c);
    LIBSSH2_SESSION *s = libssh2_session_init();
    if (!s) return 2;
    const char *kex[] = {"curve25519-sha256"}, *hk[] = {"ssh-ed25519"};
    int bad = list(s, LIBSSH2_METHOD_KEX, "KEX", kex, 1);
    bad |= list(s, LIBSSH2_METHOD_HOSTKEY, "HOSTKEY", hk, 1);
    bad |= list(s, LIBSSH2_METHOD_CRYPT_CS, "CRYPT_CS", NULL, 0);
    libssh2_session_free(s);
    libssh2_exit();
    return bad;
}
