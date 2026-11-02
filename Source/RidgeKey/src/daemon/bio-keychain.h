/* SPDX-License-Identifier: MIT */
#ifndef RK_BIO_KEYCHAIN_H
#define RK_BIO_KEYCHAIN_H
#include <Security/Security.h>
#include <sys/types.h>
#include <stdint.h>
#include <stddef.h>
#ifndef RK_BIO_SERVICE
#define RK_BIO_SERVICE "io.github.labrouss.ridgekey.goodix533c.print.v1"
#endif
OSStatus rk_bio_save(uid_t uid,int finger,const uint8_t *data,size_t size);
OSStatus rk_bio_load(uid_t uid,int finger,uint8_t **data,size_t *size);
OSStatus rk_bio_remove(uid_t uid,int finger);
void rk_bio_free(uint8_t *data,size_t size);
OSStatus rk_bio_state_save(const char *identity,const uint8_t *data,size_t size);
OSStatus rk_bio_state_load(const char *identity,uint8_t **data,size_t *size);
#endif
