#include <stdio.h>
#include <stdlib.h>
#include <wolfssl/options.h>
#include <wolfssl/wolfcrypt/settings.h>
#include <wolfssl/wolfcrypt/random.h>
#include <wolfssl/wolfcrypt/fips_test.h>
#include <wolfssl/wolfcrypt/sha256.h>
#include <wolfssl/wolfcrypt/error-crypt.h>

/**
 * FIPS Startup Validation Utility
 *
 * This utility validates FIPS configuration at container startup.
 * It performs:
 * 1. FIPS compile-time flag verification
 * 2. FIPS Known Answer Tests (CAST)
 * 3. SHA-256 cryptographic operation test
 *
 * Exit codes:
 *   0 - FIPS validation passed
 *   1 - FIPS validation failed
 */

int main(void)
{
    int ret;
    wc_Sha256 sha;
    byte hash[WC_SHA256_DIGEST_SIZE];
    const char* testData = "abc";

    printf("========================================\n");
    printf("FIPS Startup Validation\n");
    printf("========================================\n\n");

    /* Check 1: Verify FIPS compile-time configuration */
    printf("[1/3] Checking FIPS compile-time configuration...\n");
    #ifdef HAVE_FIPS
        printf("      ✓ FIPS mode: ENABLED\n");
        #ifdef HAVE_FIPS_VERSION
            printf("      ✓ FIPS version: %d\n", HAVE_FIPS_VERSION);
            if (HAVE_FIPS_VERSION < 5) {
                printf("      ✗ ERROR: FIPS version must be 5 or higher\n");
                return 1;
            }
        #else
            printf("      ⚠ FIPS version macro not available\n");
        #endif
    #else
        printf("      ✗ ERROR: FIPS mode is DISABLED\n");
        printf("      This binary was not compiled with FIPS support\n");
        return 1;
    #endif

    /* Check 2: Run FIPS Known Answer Tests (CAST) */
    printf("\n[2/3] Running FIPS Known Answer Tests (CAST)...\n");
    wc_SetSeed_Cb(wc_GenerateSeed);
    ret = wc_RunAllCast_fips();
    if (ret != 0) {
        printf("      ✗ FIPS CAST FAILED (error code: %d)\n", ret);
        printf("      FIPS cryptographic module validation failed\n");
        return 1;
    }
    printf("      ✓ FIPS CAST: PASSED\n");

    /* Check 3: Validate SHA-256 operation with known test vector */
    printf("\n[3/3] Validating SHA-256 cryptographic operation...\n");
    ret = wc_InitSha256(&sha);
    if (ret != 0) {
        printf("      ✗ SHA-256 initialization failed (error code: %d)\n", ret);
        return 1;
    }

    ret = wc_Sha256Update(&sha, (const byte*)testData, 3);
    if (ret != 0) {
        printf("      ✗ SHA-256 update failed (error code: %d)\n", ret);
        return 1;
    }

    ret = wc_Sha256Final(&sha, hash);
    if (ret != 0) {
        printf("      ✗ SHA-256 finalization failed (error code: %d)\n", ret);
        return 1;
    }

    /* Verify against known test vector */
    const byte expected[WC_SHA256_DIGEST_SIZE] = {
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad
    };

    int match = 1;
    for (int i = 0; i < WC_SHA256_DIGEST_SIZE; i++) {
        if (hash[i] != expected[i]) {
            match = 0;
            break;
        }
    }

    if (!match) {
        printf("      ✗ SHA-256 test vector mismatch\n");
        printf("      Cryptographic operation produced incorrect result\n");
        return 1;
    }

    printf("      ✓ SHA-256 test vector: PASSED\n");

    /* All checks passed */
    printf("\n========================================\n");
    printf("✓ FIPS VALIDATION PASSED\n");
    printf("========================================\n");
    printf("FIPS 140-3 compliant cryptography verified\n");
    printf("Container startup authorized\n\n");

    return 0;
}
