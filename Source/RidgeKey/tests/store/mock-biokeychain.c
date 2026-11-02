/* SPDX-License-Identifier: MIT -- test-only, never linked into ridgekeyd */
#include "bio-keychain.h"
#include <glib.h>
#include <stdlib.h>
#include <string.h>
static GHashTable *items;
int mock_bio_fail_write,mock_bio_fail_read;
static char *key(uid_t uid,int finger){return g_strdup_printf("%u:%d",(unsigned)uid,finger);}
OSStatus rk_bio_save(uid_t uid,int finger,const uint8_t *data,size_t size) {
    if(mock_bio_fail_write)return errSecAuthFailed;
    if(!items)items=g_hash_table_new_full(g_str_hash,g_str_equal,g_free,(GDestroyNotify)g_bytes_unref);
    g_hash_table_replace(items,key(uid,finger),g_bytes_new(data,size));return errSecSuccess;
}
OSStatus rk_bio_load(uid_t uid,int finger,uint8_t **data,size_t *size) {
    *data=NULL;*size=0;if(mock_bio_fail_read)return errSecAuthFailed;
    g_autofree char *k=key(uid,finger);GBytes *b=items?g_hash_table_lookup(items,k):NULL;
    if(!b)return errSecItemNotFound;
    gconstpointer p=g_bytes_get_data(b,size);*data=malloc(*size);if(!*data)return errSecAllocate;memcpy(*data,p,*size);return errSecSuccess;
}
OSStatus rk_bio_remove(uid_t uid,int finger){g_autofree char *k=key(uid,finger);if(items)g_hash_table_remove(items,k);return errSecSuccess;}
void rk_bio_free(uint8_t *data,size_t size){if(data){memset(data,0,size);free(data);}}
