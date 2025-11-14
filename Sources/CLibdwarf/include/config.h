#ifndef LIBDWARF_SWIFT_CONFIG_H
#define LIBDWARF_SWIFT_CONFIG_H

#include <stdint.h>

/* Basic POSIX headers available on Darwin/Linux */
#define AC_APPLE_UNIVERSAL_BUILD 0
#define CRAY_STACKSEG_END 0
#define HAVE_DLFCN_H 1
#define HAVE_UNISTD_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDDEF_H 1
#define HAVE_FCNTL_H 1
#define HAVE_SYS_STAT_H 1
#define STDC_HEADERS 1

/* Optional/legacy headers that are not needed on modern systems */
#undef HAVE_MALLOC_H
#undef HAVE_STDAFX_H

/* Memory mapping is available on macOS */
#define HAVE_FULL_MMAP 1

/* Endianness is determined at compile time */
#if defined(__BIG_ENDIAN__)
#define WORDS_BIGENDIAN 1
#else
#undef WORDS_BIGENDIAN
#endif

/* Compression backends are disabled for now */
#undef HAVE_ZLIB
#undef HAVE_ZLIB_H
#undef HAVE_ZSTD
#undef HAVE_ZSTD_H

/* Package identity metadata */
#define PACKAGE "libdwarf"
#define PACKAGE_NAME "libdwarf"
#define PACKAGE_TARNAME "libdwarf"
#define PACKAGE_VERSION "0.0.0"
#define PACKAGE_STRING PACKAGE " " PACKAGE_VERSION
#define PACKAGE_BUGREPORT ""
#define PACKAGE_URL "https://www.prevanders.net/libdwarf.html"
#define LT_OBJDIR ".libs/"

/* Stack direction is not known at compile time */
#define STACK_DIRECTION 0

#endif /* LIBDWARF_SWIFT_CONFIG_H */
