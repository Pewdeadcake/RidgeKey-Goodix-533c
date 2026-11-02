/* SPDX-License-Identifier: MIT
 * Host-matched Milan templates live in the encrypted System keychain, not
 * plaintext .print files. Same root-only daemon boundary as RidgeKey secret.c.
 * This service is separate from stored login passwords and no password is
 * needed to enroll or to use the diagnostic identify operation as root.
 */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include "bio-keychain.h"
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define BIO_SERVICE RK_BIO_SERVICE
#define BIO_MAX (16u*1024u*1024u)
static void erase(void *p,size_t n){volatile uint8_t *v=p;while(n--)*v++=0;}
void rk_bio_free(uint8_t *data,size_t size){if(data){erase(data,size);free(data);}}
static OSStatus open_store(const char *account,SecKeychainRef *kc) {
    if(geteuid()!=0)return errSecAuthFailed;
    if(!account || !*account || strlen(account)>127)return errSecParam;
    for(const char *p=account;*p;++p)if(!((*p>='a'&&*p<='z')||(*p>='0'&&*p<='9')||*p==':'||*p=='-'||*p=='.'))return errSecParam;
    SecKeychainSetUserInteractionAllowed(false);
    return SecKeychainOpen("/Library/Keychains/System.keychain",kc);
}
static OSStatus find(SecKeychainRef kc,const char *account,SecKeychainItemRef *item,UInt32 *size,void **data) {
    return SecKeychainFindGenericPassword(kc,(UInt32)strlen(BIO_SERVICE),BIO_SERVICE,
        (UInt32)strlen(account),account,size,data,item);
}
static SecAccessRef access_for_root(void) {
    /* UID ownership instead of an any-application decrypt ACL. The install
     * test must prove a separate non-root process cannot read the item. */
    CFErrorRef error=NULL;
    SecAccessRef access=SecAccessCreateWithOwnerAndACL(0,0,kSecUseOnlyUID,NULL,&error);
    if(error)CFRelease(error);return access;
}
static OSStatus save_named(const char *account,const uint8_t *data,size_t size) {
    if(!data || !size || size>BIO_MAX)return errSecParam;
    SecKeychainRef kc=NULL;SecKeychainItemRef item=NULL;
    OSStatus st=open_store(account,&kc);if(st!=errSecSuccess)return st;
    st=find(kc,account,&item,NULL,NULL);
    if(st==errSecSuccess)st=SecKeychainItemModifyAttributesAndData(item,NULL,(UInt32)size,data);
    else if(st==errSecItemNotFound) {
        SecAccessRef access=access_for_root();
        if(!access)st=errSecAuthFailed;
        else {
            const char label[]="RidgeKey 533c - encrypted biometric template";
            SecKeychainAttribute attrs[3]={
                {kSecServiceItemAttr,(UInt32)strlen(BIO_SERVICE),(void *)BIO_SERVICE},
                {kSecAccountItemAttr,(UInt32)strlen(account),(void *)account},
                {kSecLabelItemAttr,sizeof label-1,(void *)label}};
            SecKeychainAttributeList list={3,attrs};
            st=SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass,&list,(UInt32)size,data,kc,access,&item);
            CFRelease(access);
        }
    }
    if(item)CFRelease(item);CFRelease(kc);return st;
}
static OSStatus load_named(const char *account,uint8_t **data,size_t *size) {
    if(!data || !size)return errSecParam;*data=NULL;*size=0;
    SecKeychainRef kc=NULL;SecKeychainItemRef item=NULL;UInt32 count=0;void *value=NULL;
    OSStatus st=open_store(account,&kc);if(st!=errSecSuccess)return st;
    st=find(kc,account,&item,&count,&value);
    if(st==errSecSuccess) {
        if(!count || count>BIO_MAX)st=errSecDecode;
        else {
            *data=malloc(count);
            if(!*data)st=errSecAllocate;else {memcpy(*data,value,count);*size=count;}
        }
    }
    if(value){erase(value,count);SecKeychainItemFreeContent(NULL,value);}
    if(item)CFRelease(item);CFRelease(kc);return st;
}
OSStatus rk_bio_remove(uid_t uid,int finger) {
    if(finger<1 || finger>10)return errSecParam;
    char account[64];snprintf(account,sizeof account,"%u:%d",(unsigned)uid,finger);
    SecKeychainRef kc=NULL;SecKeychainItemRef item=NULL;
    OSStatus st=open_store(account,&kc);if(st!=errSecSuccess)return st;
    st=find(kc,account,&item,NULL,NULL);if(st==errSecSuccess)st=SecKeychainItemDelete(item);
    if(item)CFRelease(item);CFRelease(kc);return st==errSecItemNotFound?errSecSuccess:st;
}
OSStatus rk_bio_save(uid_t uid,int finger,const uint8_t *data,size_t size) {
    if(finger<1 || finger>10)return errSecParam;
    char account[64];snprintf(account,sizeof account,"%u:%d",(unsigned)uid,finger);
    return save_named(account,data,size);
}
OSStatus rk_bio_load(uid_t uid,int finger,uint8_t **data,size_t *size) {
    if(finger<1 || finger>10)return errSecParam;
    char account[64];snprintf(account,sizeof account,"%u:%d",(unsigned)uid,finger);
    return load_named(account,data,size);
}
static int state_identity(const char *identity) {
    const char prefix[]="goodix53x5-preprocess-";
    size_t n=sizeof prefix-1;
    if(!identity || strlen(identity)!=n+64+4 || strncmp(identity,prefix,n) || strcmp(identity+n+64,".bin"))return 0;
    for(size_t i=n;i<n+64;++i)if(!((identity[i]>='0'&&identity[i]<='9')||(identity[i]>='a'&&identity[i]<='f')))return 0;
    return 1;
}
OSStatus rk_bio_state_save(const char *identity,const uint8_t *data,size_t size) {
    return state_identity(identity)?save_named(identity,data,size):errSecParam;
}
OSStatus rk_bio_state_load(const char *identity,uint8_t **data,size_t *size) {
    return state_identity(identity)?load_named(identity,data,size):errSecParam;
}
