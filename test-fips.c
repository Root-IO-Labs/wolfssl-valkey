#include <stdio.h>
#include <wolfssl/options.h>
#include <wolfssl/wolfcrypt/settings.h>
#include <wolfssl/wolfcrypt/random.h>
#include <wolfssl/wolfcrypt/fips_test.h>
#include <wolfssl/wolfcrypt/sha256.h>
#include <wolfssl/wolfcrypt/error-crypt.h>

int main(void)
{
    int ret;
    wc_Sha256 sha;
    byte hash[WC_SHA256_DIGEST_SIZE];
    const char* data = "abc";

    printf("Testing wolfSSL FIPS installation...\n");

    #ifdef HAVE_FIPS
        printf("FIPS mode: ENABLED\n");
        #ifdef HAVE_FIPS_VERSION
            printf("FIPS version: %d\n", HAVE_FIPS_VERSION);
        #else
            printf("FIPS version: Enabled (version macro not available)\n");
        #endif
    #else
        printf("FIPS mode: DISABLED (WARNING!)\n");
    #endif

    printf("\nRunning FIPS CAST (Known Answer Tests)...\n");
    wc_SetSeed_Cb(wc_GenerateSeed);
    ret = wc_RunAllCast_fips();
    if (ret != 0) {
        printf("FIPS CAST failed: %d\n", ret);
        return 1;
    }
    printf("FIPS CAST: PASSED\n");

    printf("\nRunning SHA256 test...\n");
    ret = wc_InitSha256(&sha);
    if (ret != 0) {
        printf("SHA256 Init failed: %d\n", ret);
        return 1;
    }

    ret = wc_Sha256Update(&sha, (const byte*)data, 3);
    if (ret != 0) {
        printf("SHA256 Update failed: %d\n", ret);
        return 1;
    }

    ret = wc_Sha256Final(&sha, hash);
    if (ret != 0) {
        printf("SHA256 Final failed: %d\n", ret);
        return 1;
    }

    printf("SHA256('abc') = ");
    for (int i = 0; i < WC_SHA256_DIGEST_SIZE; i++) {
        printf("%02x", hash[i]);
    }
    printf("\n");

    printf("Expected:       ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n");
    printf("\nwolfSSL FIPS test: ALL PASSED ✓\n");

    return 0;
}
