/* SPDX-License-Identifier: MIT
 * Real macOS Keychain preflight with synthetic bytes, NEVER fingerprint data.
 * Separate processes verify root write/read and direct non-root API denial.
 */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include "bio-keychain.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#define TEST_UID ((uid_t)4294967000u)
#define TEST_SIZE (1024u*1024u+4096u)
int main(int argc,char **argv) {
    static uint8_t expected[TEST_SIZE];
    for(size_t i=0;i<sizeof expected;++i)expected[i]=(uint8_t)(i*29u+7u);
    if(argc!=2)return 2;OSStatus st;
#ifdef RK_PREFLIGHT_READER
    puts("Independent reader binary: tests persistence without trusting the writer's code identity.");
    if(strcmp(argv[1],"--read") && strcmp(argv[1],"--deny-user"))return 2;
#endif
    if(!strcmp(argv[1],"--write")) {
        st=rk_bio_save(TEST_UID,10,expected,sizeof expected);
        printf("KEYCHAIN_TEST_WRITE status=%d\n",(int)st);return st==errSecSuccess?0:1;
    }
    if(!strcmp(argv[1],"--read")) {
        uint8_t *data=NULL;size_t len=0;st=rk_bio_load(TEST_UID,10,&data,&len);
        int ok=st==errSecSuccess && len==sizeof expected && !memcmp(data,expected,len);
        rk_bio_free(data,len);printf("KEYCHAIN_TEST_ROOT_READ %s status=%d\n",ok?"PASS":"FAIL",(int)st);return ok?0:1;
    }
    if(!strcmp(argv[1],"--deny-user")) {
        if(geteuid()==0)return 2;
        SecKeychainSetUserInteractionAllowed(false);SecKeychainRef kc=NULL;
        st=SecKeychainOpen("/Library/Keychains/System.keychain",&kc);
        if(st!=errSecSuccess){printf("KEYCHAIN_TEST_USER_OPEN_DENIED status=%d\n",(int)st);return 0;}
        const char service[]=RK_BIO_SERVICE,account[]="4294967000:10";
        UInt32 len=0;void *data=NULL;
        st=SecKeychainFindGenericPassword(kc,sizeof service-1,service,sizeof account-1,account,&len,&data,NULL);
        if(data)SecKeychainItemFreeContent(NULL,data);CFRelease(kc);
        /* Harness must first write and read this item as root. Some Keychain
         * versions conceal an inaccessible existing item as item-not-found. */
        int ok=st==errSecAuthFailed || st==errSecInteractionNotAllowed || st==errSecNoAccessForItem || st==errSecInteractionRequired || st==errSecItemNotFound;
        printf("KEYCHAIN_TEST_DIRECT_USER_READ %s status=%d\n",ok?"DENIED":"FAIL",(int)st);return ok?0:1;
    }
    if(!strcmp(argv[1],"--delete")){st=rk_bio_remove(TEST_UID,10);printf("KEYCHAIN_TEST_DELETE status=%d\n",(int)st);return st==errSecSuccess?0:1;}
    return 2;
}
