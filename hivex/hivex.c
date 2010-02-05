/* hivex - Windows Registry "hive" extraction library.
 * Copyright (C) 2009-2010 Red Hat Inc.
 * Derived from code by Petter Nordahl-Hagen under a compatible license:
 *   Copyright (c) 1997-2007 Petter Nordahl-Hagen.
 * Derived from code by Markus Stephany under a compatible license:
 *   Copyright (c) 2000-2004, Markus Stephany.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation;
 * version 2.1 of the License.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * See file LICENSE for the full license.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <inttypes.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <iconv.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <assert.h>

#include "c-ctype.h"
#include "full-read.h"
#include "full-write.h"

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

#define STREQ(a,b) (strcmp((a),(b)) == 0)
#define STRCASEEQ(a,b) (strcasecmp((a),(b)) == 0)
//#define STRNEQ(a,b) (strcmp((a),(b)) != 0)
//#define STRCASENEQ(a,b) (strcasecmp((a),(b)) != 0)
#define STREQLEN(a,b,n) (strncmp((a),(b),(n)) == 0)
//#define STRCASEEQLEN(a,b,n) (strncasecmp((a),(b),(n)) == 0)
//#define STRNEQLEN(a,b,n) (strncmp((a),(b),(n)) != 0)
//#define STRCASENEQLEN(a,b,n) (strncasecmp((a),(b),(n)) != 0)
#define STRPREFIX(a,b) (strncmp((a),(b),strlen((b))) == 0)

#include "hivex.h"
#include "byte_conversions.h"

/* These limits are in place to stop really stupid stuff and/or exploits. */
#define HIVEX_MAX_SUBKEYS       10000
#define HIVEX_MAX_VALUES         1000
#define HIVEX_MAX_VALUE_LEN   1000000
#define HIVEX_MAX_ALLOCATION  1000000

static char *windows_utf16_to_utf8 (/* const */ char *input, size_t len);

struct hive_h {
  char *filename;
  int fd;
  size_t size;
  int msglvl;
  int writable;

  /* Registry file, memory mapped if read-only, or malloc'd if writing. */
  union {
    char *addr;
    struct ntreg_header *hdr;
  };

  /* Use a bitmap to store which file offsets are valid (point to a
   * used block).  We only need to store 1 bit per 32 bits of the file
   * (because blocks are 4-byte aligned).  We found that the average
   * block size in a registry file is ~50 bytes.  So roughly 1 in 12
   * bits in the bitmap will be set, making it likely a more efficient
   * structure than a hash table.
   */
  char *bitmap;
#define BITMAP_SET(bitmap,off) (bitmap[(off)>>5] |= 1 << (((off)>>2)&7))
#define BITMAP_CLR(bitmap,off) (bitmap[(off)>>5] &= ~ (1 << (((off)>>2)&7)))
#define BITMAP_TST(bitmap,off) (bitmap[(off)>>5] & (1 << (((off)>>2)&7)))
#define IS_VALID_BLOCK(h,off)               \
  (((off) & 3) == 0 &&                      \
   (off) >= 0x1000 &&                       \
   (off) < (h)->size &&                     \
   BITMAP_TST((h)->bitmap,(off)))

  /* Fields from the header, extracted from little-endianness hell. */
  size_t rootoffs;              /* Root key offset (always an nk-block). */
  size_t endpages;              /* Offset of end of pages. */

  /* For writing. */
  size_t endblocks;             /* Offset to next block allocation (0
                                   if not allocated anything yet). */
};

/* NB. All fields are little endian. */
struct ntreg_header {
  char magic[4];                /* "regf" */
  uint32_t sequence1;
  uint32_t sequence2;
  char last_modified[8];
  uint32_t major_ver;           /* 1 */
  uint32_t minor_ver;           /* 3 */
  uint32_t unknown5;            /* 0 */
  uint32_t unknown6;            /* 1 */
  uint32_t offset;              /* offset of root key record - 4KB */
  uint32_t blocks;              /* pointer AFTER last hbin in file - 4KB */
  uint32_t unknown7;            /* 1 */
  /* 0x30 */
  char name[64];                /* original file name of hive */
  char unknown_guid1[16];
  char unknown_guid2[16];
  /* 0x90 */
  uint32_t unknown8;
  char unknown_guid3[16];
  uint32_t unknown9;
  /* 0xa8 */
  char unknown10[340];
  /* 0x1fc */
  uint32_t csum;                /* checksum: xor of dwords 0-0x1fb. */
  /* 0x200 */
  char unknown11[3528];
  /* 0xfc8 */
  char unknown_guid4[16];
  char unknown_guid5[16];
  char unknown_guid6[16];
  uint32_t unknown12;
  uint32_t unknown13;
  /* 0x1000 */
} __attribute__((__packed__));

struct ntreg_hbin_page {
  char magic[4];                /* "hbin" */
  uint32_t offset_first;        /* offset from 1st block */
  uint32_t page_size;           /* size of this page (multiple of 4KB) */
  char unknown[20];
  /* Linked list of blocks follows here. */
} __attribute__((__packed__));

struct ntreg_hbin_block {
  int32_t seg_len;              /* length of this block (-ve for used block) */
  char id[2];                   /* the block type (eg. "nk" for nk record) */
  /* Block data follows here. */
} __attribute__((__packed__));

#define BLOCK_ID_EQ(h,offs,eqid) \
  (STREQLEN (((struct ntreg_hbin_block *)((h)->addr + (offs)))->id, (eqid), 2))

static size_t
block_len (hive_h *h, size_t blkoff, int *used)
{
  struct ntreg_hbin_block *block;
  block = (struct ntreg_hbin_block *) (h->addr + blkoff);

  int32_t len = le32toh (block->seg_len);
  if (len < 0) {
    if (used) *used = 1;
    len = -len;
  } else {
    if (used) *used = 0;
  }

  return (size_t) len;
}

struct ntreg_nk_record {
  int32_t seg_len;              /* length (always -ve because used) */
  char id[2];                   /* "nk" */
  uint16_t flags;
  char timestamp[8];
  uint32_t unknown1;
  uint32_t parent;              /* offset of owner/parent */
  uint32_t nr_subkeys;          /* number of subkeys */
  uint32_t nr_subkeys_volatile;
  uint32_t subkey_lf;           /* lf record containing list of subkeys */
  uint32_t subkey_lf_volatile;
  uint32_t nr_values;           /* number of values */
  uint32_t vallist;             /* value-list record */
  uint32_t sk;                  /* offset of sk-record */
  uint32_t classname;           /* offset of classname record */
  uint16_t max_subkey_name_len; /* maximum length of a subkey name in bytes
                                   if the subkey was reencoded as UTF-16LE */
  uint16_t unknown2;
  uint32_t unknown3;
  uint32_t max_vk_name_len;     /* maximum length of any vk name in bytes
                                   if the name was reencoded as UTF-16LE */
  uint32_t max_vk_data_len;     /* maximum length of any vk data in bytes */
  uint32_t unknown6;
  uint16_t name_len;            /* length of name */
  uint16_t classname_len;       /* length of classname */
  char name[1];                 /* name follows here */
} __attribute__((__packed__));

struct ntreg_lf_record {
  int32_t seg_len;
  char id[2];                   /* "lf"|"lh" */
  uint16_t nr_keys;             /* number of keys in this record */
  struct {
    uint32_t offset;            /* offset of nk-record for this subkey */
    char hash[4];               /* hash of subkey name */
  } keys[1];
} __attribute__((__packed__));

struct ntreg_ri_record {
  int32_t seg_len;
  char id[2];                   /* "ri" */
  uint16_t nr_offsets;          /* number of pointers to lh records */
  uint32_t offset[1];           /* list of pointers to lh records */
} __attribute__((__packed__));

/* This has no ID header. */
struct ntreg_value_list {
  int32_t seg_len;
  uint32_t offset[1];           /* list of pointers to vk records */
} __attribute__((__packed__));

struct ntreg_vk_record {
  int32_t seg_len;              /* length (always -ve because used) */
  char id[2];                   /* "vk" */
  uint16_t name_len;            /* length of name */
  /* length of the data:
   * If data_len is <= 4, then it's stored inline.
   * Top bit is set to indicate inline.
   */
  uint32_t data_len;
  uint32_t data_offset;         /* pointer to the data (or data if inline) */
  uint32_t data_type;           /* type of the data */
  uint16_t flags;               /* bit 0 set => key name ASCII,
                                   bit 0 clr => key name UTF-16.
                                   Only seen ASCII here in the wild.
                                   NB: this is CLEAR for default key. */
  uint16_t unknown2;
  char name[1];                 /* key name follows here */
} __attribute__((__packed__));

struct ntreg_sk_record {
  int32_t seg_len;              /* length (always -ve because used) */
  char id[2];                   /* "sk" */
  uint16_t unknown1;
  uint32_t sk_next;             /* linked into a circular list */
  uint32_t sk_prev;
  uint32_t refcount;            /* reference count */
  uint32_t sec_len;             /* length of security info */
  char sec_desc[1];             /* security info follows */
} __attribute__((__packed__));

static uint32_t
header_checksum (const hive_h *h)
{
  uint32_t *daddr = (uint32_t *) h->addr;
  size_t i;
  uint32_t sum = 0;

  for (i = 0; i < 0x1fc / 4; ++i) {
    sum ^= le32toh (*daddr);
    daddr++;
  }

  return sum;
}

hive_h *
hivex_open (const char *filename, int flags)
{
  hive_h *h = NULL;

  assert (sizeof (struct ntreg_header) == 0x1000);
  assert (offsetof (struct ntreg_header, csum) == 0x1fc);

  h = calloc (1, sizeof *h);
  if (h == NULL)
    goto error;

  h->msglvl = flags & HIVEX_OPEN_MSGLVL_MASK;

  const char *debug = getenv ("HIVEX_DEBUG");
  if (debug && STREQ (debug, "1"))
    h->msglvl = 2;

  if (h->msglvl >= 2)
    fprintf (stderr, "hivex_open: created handle %p\n", h);

  h->writable = !!(flags & HIVEX_OPEN_WRITE);
  h->filename = strdup (filename);
  if (h->filename == NULL)
    goto error;

  h->fd = open (filename, O_RDONLY | O_CLOEXEC);
  if (h->fd == -1)
    goto error;

  struct stat statbuf;
  if (fstat (h->fd, &statbuf) == -1)
    goto error;

  h->size = statbuf.st_size;

  if (!h->writable) {
    h->addr = mmap (NULL, h->size, PROT_READ, MAP_SHARED, h->fd, 0);
    if (h->addr == MAP_FAILED)
      goto error;

    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_open: mapped file at %p\n", h->addr);
  } else {
    h->addr = malloc (h->size);
    if (h->addr == NULL)
      goto error;

    if (full_read (h->fd, h->addr, h->size) < h->size)
      goto error;
  }

  /* Check header. */
  if (h->hdr->magic[0] != 'r' ||
      h->hdr->magic[1] != 'e' ||
      h->hdr->magic[2] != 'g' ||
      h->hdr->magic[3] != 'f') {
    fprintf (stderr, "hivex: %s: not a Windows NT Registry hive file\n",
             filename);
    errno = ENOTSUP;
    goto error;
  }

  /* Check major version. */
  uint32_t major_ver = le32toh (h->hdr->major_ver);
  if (major_ver != 1) {
    fprintf (stderr,
             "hivex: %s: hive file major version %" PRIu32 " (expected 1)\n",
             filename, major_ver);
    errno = ENOTSUP;
    goto error;
  }

  h->bitmap = calloc (1 + h->size / 32, 1);
  if (h->bitmap == NULL)
    goto error;

  /* Header checksum. */
  uint32_t sum = header_checksum (h);
  if (sum != le32toh (h->hdr->csum)) {
    fprintf (stderr, "hivex: %s: bad checksum in hive header\n", filename);
    errno = EINVAL;
    goto error;
  }

  if (h->msglvl >= 2) {
    char *name = windows_utf16_to_utf8 (h->hdr->name, 64);

    fprintf (stderr,
             "hivex_open: header fields:\n"
             "  file version             %" PRIu32 ".%" PRIu32 "\n"
             "  sequence nos             %" PRIu32 " %" PRIu32 "\n"
             "    (sequences nos should match if hive was synched at shutdown)\n"
             "  original file name       %s\n"
             "    (only 32 chars are stored, name is probably truncated)\n"
             "  root offset              0x%x + 0x1000\n"
             "  end of last page         0x%x + 0x1000 (total file size 0x%zx)\n"
             "  checksum                 0x%x (calculated 0x%x)\n",
             major_ver, le32toh (h->hdr->minor_ver),
             le32toh (h->hdr->sequence1), le32toh (h->hdr->sequence2),
             name ? name : "(conversion failed)",
             le32toh (h->hdr->offset),
             le32toh (h->hdr->blocks), h->size,
             le32toh (h->hdr->csum), sum);
    free (name);
  }

  h->rootoffs = le32toh (h->hdr->offset) + 0x1000;
  h->endpages = le32toh (h->hdr->blocks) + 0x1000;

  if (h->msglvl >= 2)
    fprintf (stderr, "hivex_open: root offset = 0x%zx\n", h->rootoffs);

  /* We'll set this flag when we see a block with the root offset (ie.
   * the root block).
   */
  int seen_root_block = 0, bad_root_block = 0;

  /* Collect some stats. */
  size_t pages = 0;           /* Number of hbin pages read. */
  size_t smallest_page = SIZE_MAX, largest_page = 0;
  size_t blocks = 0;          /* Total number of blocks found. */
  size_t smallest_block = SIZE_MAX, largest_block = 0, blocks_bytes = 0;
  size_t used_blocks = 0;     /* Total number of used blocks found. */
  size_t used_size = 0;       /* Total size (bytes) of used blocks. */

  /* Read the pages and blocks.  The aim here is to be robust against
   * corrupt or malicious registries.  So we make sure the loops
   * always make forward progress.  We add the address of each block
   * we read to a hash table so pointers will only reference the start
   * of valid blocks.
   */
  size_t off;
  struct ntreg_hbin_page *page;
  for (off = 0x1000; off < h->size; off += le32toh (page->page_size)) {
    if (off >= h->endpages)
      break;

    page = (struct ntreg_hbin_page *) (h->addr + off);
    if (page->magic[0] != 'h' ||
        page->magic[1] != 'b' ||
        page->magic[2] != 'i' ||
        page->magic[3] != 'n') {
      fprintf (stderr, "hivex: %s: trailing garbage at end of file (at 0x%zx, after %zu pages)\n",
               filename, off, pages);
      errno = ENOTSUP;
      goto error;
    }

    size_t page_size = le32toh (page->page_size);
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_open: page at 0x%zx, size %zu\n", off, page_size);
    pages++;
    if (page_size < smallest_page) smallest_page = page_size;
    if (page_size > largest_page) largest_page = page_size;

    if (page_size <= sizeof (struct ntreg_hbin_page) ||
        (page_size & 0x0fff) != 0) {
      fprintf (stderr, "hivex: %s: page size %zu at 0x%zx, bad registry\n",
               filename, page_size, off);
      errno = ENOTSUP;
      goto error;
    }

    /* Read the blocks in this page. */
    size_t blkoff;
    struct ntreg_hbin_block *block;
    size_t seg_len;
    for (blkoff = off + 0x20;
         blkoff < off + page_size;
         blkoff += seg_len) {
      blocks++;

      int is_root = blkoff == h->rootoffs;
      if (is_root)
        seen_root_block = 1;

      block = (struct ntreg_hbin_block *) (h->addr + blkoff);
      int used;
      seg_len = block_len (h, blkoff, &used);
      if (seg_len <= 4 || (seg_len & 3) != 0) {
        fprintf (stderr, "hivex: %s: block size %" PRIu32 " at 0x%zx, bad registry\n",
                 filename, le32toh (block->seg_len), blkoff);
        errno = ENOTSUP;
        goto error;
      }

      if (h->msglvl >= 2)
        fprintf (stderr, "hivex_open: %s block id %d,%d at 0x%zx size %zu%s\n",
                 used ? "used" : "free", block->id[0], block->id[1], blkoff,
                 seg_len, is_root ? " (root)" : "");

      blocks_bytes += seg_len;
      if (seg_len < smallest_block) smallest_block = seg_len;
      if (seg_len > largest_block) largest_block = seg_len;

      if (is_root && !used)
        bad_root_block = 1;

      if (used) {
        used_blocks++;
        used_size += seg_len;

        /* Root block must be an nk-block. */
        if (is_root && (block->id[0] != 'n' || block->id[1] != 'k'))
          bad_root_block = 1;

        /* Note this blkoff is a valid address. */
        BITMAP_SET (h->bitmap, blkoff);
      }
    }
  }

  if (!seen_root_block) {
    fprintf (stderr, "hivex: %s: no root block found\n", filename);
    errno = ENOTSUP;
    goto error;
  }

  if (bad_root_block) {
    fprintf (stderr, "hivex: %s: bad root block (free or not nk)\n", filename);
    errno = ENOTSUP;
    goto error;
  }

  if (h->msglvl >= 1)
    fprintf (stderr,
             "hivex_open: successfully read Windows Registry hive file:\n"
             "  pages:          %zu [sml: %zu, lge: %zu]\n"
             "  blocks:         %zu [sml: %zu, avg: %zu, lge: %zu]\n"
             "  blocks used:    %zu\n"
             "  bytes used:     %zu\n",
             pages, smallest_page, largest_page,
             blocks, smallest_block, blocks_bytes / blocks, largest_block,
             used_blocks, used_size);

  return h;

 error:;
  int err = errno;
  if (h) {
    free (h->bitmap);
    if (h->addr && h->size && h->addr != MAP_FAILED) {
      if (!h->writable)
        munmap (h->addr, h->size);
      else
        free (h->addr);
    }
    if (h->fd >= 0)
      close (h->fd);
    free (h->filename);
    free (h);
  }
  errno = err;
  return NULL;
}

int
hivex_close (hive_h *h)
{
  int r;

  free (h->bitmap);
  if (!h->writable)
    munmap (h->addr, h->size);
  else
    free (h->addr);
  r = close (h->fd);
  free (h->filename);
  free (h);

  return r;
}

/*----------------------------------------------------------------------
 * Reading.
 */

hive_node_h
hivex_root (hive_h *h)
{
  hive_node_h ret = h->rootoffs;
  if (!IS_VALID_BLOCK (h, ret)) {
    errno = ENOKEY;
    return 0;
  }
  return ret;
}

char *
hivex_node_name (hive_h *h, hive_node_h node)
{
  if (!IS_VALID_BLOCK (h, node) || !BLOCK_ID_EQ (h, node, "nk")) {
    errno = EINVAL;
    return NULL;
  }

  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + node);

  /* AFAIK the node name is always plain ASCII, so no conversion
   * to UTF-8 is necessary.  However we do need to nul-terminate
   * the string.
   */

  /* nk->name_len is unsigned, 16 bit, so this is safe ...  However
   * we have to make sure the length doesn't exceed the block length.
   */
  size_t len = le16toh (nk->name_len);
  size_t seg_len = block_len (h, node, NULL);
  if (sizeof (struct ntreg_nk_record) + len - 1 > seg_len) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_name: returning EFAULT because node name is too long (%zu, %zu)\n",
              len, seg_len);
    errno = EFAULT;
    return NULL;
  }

  char *ret = malloc (len + 1);
  if (ret == NULL)
    return NULL;
  memcpy (ret, nk->name, len);
  ret[len] = '\0';
  return ret;
}

#if 0
/* I think the documentation for the sk and classname fields in the nk
 * record is wrong, or else the offset field is in the wrong place.
 * Otherwise this makes no sense.  Disabled this for now -- it's not
 * useful for reading the registry anyway.
 */

hive_security_h
hivex_node_security (hive_h *h, hive_node_h node)
{
  if (!IS_VALID_BLOCK (h, node) || !BLOCK_ID_EQ (h, node, "nk")) {
    errno = EINVAL;
    return 0;
  }

  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + node);

  hive_node_h ret = le32toh (nk->sk);
  ret += 0x1000;
  if (!IS_VALID_BLOCK (h, ret)) {
    errno = EFAULT;
    return 0;
  }
  return ret;
}

hive_classname_h
hivex_node_classname (hive_h *h, hive_node_h node)
{
  if (!IS_VALID_BLOCK (h, node) || !BLOCK_ID_EQ (h, node, "nk")) {
    errno = EINVAL;
    return 0;
  }

  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + node);

  hive_node_h ret = le32toh (nk->classname);
  ret += 0x1000;
  if (!IS_VALID_BLOCK (h, ret)) {
    errno = EFAULT;
    return 0;
  }
  return ret;
}
#endif

/* Structure for returning 0-terminated lists of offsets (nodes,
 * values, etc).
 */
struct offset_list {
  size_t *offsets;
  size_t len;
  size_t alloc;
};

static void
init_offset_list (struct offset_list *list)
{
  list->len = 0;
  list->alloc = 0;
  list->offsets = NULL;
}

#define INIT_OFFSET_LIST(name) \
  struct offset_list name; \
  init_offset_list (&name)

/* Preallocates the offset_list, but doesn't make the contents longer. */
static int
grow_offset_list (struct offset_list *list, size_t alloc)
{
  assert (alloc >= list->len);
  size_t *p = realloc (list->offsets, alloc * sizeof (size_t));
  if (p == NULL)
    return -1;
  list->offsets = p;
  list->alloc = alloc;
  return 0;
}

static int
add_to_offset_list (struct offset_list *list, size_t offset)
{
  if (list->len >= list->alloc) {
    if (grow_offset_list (list, list->alloc ? list->alloc * 2 : 4) == -1)
      return -1;
  }
  list->offsets[list->len] = offset;
  list->len++;
  return 0;
}

static void
free_offset_list (struct offset_list *list)
{
  free (list->offsets);
}

static size_t *
return_offset_list (struct offset_list *list)
{
  if (add_to_offset_list (list, 0) == -1)
    return NULL;
  return list->offsets;         /* caller frees */
}

/* Iterate over children, returning child nodes and intermediate blocks. */
#define GET_CHILDREN_NO_CHECK_NK 1

static int
get_children (hive_h *h, hive_node_h node,
              hive_node_h **children_ret, size_t **blocks_ret,
              int flags)
{
  if (!IS_VALID_BLOCK (h, node) || !BLOCK_ID_EQ (h, node, "nk")) {
    errno = EINVAL;
    return -1;
  }

  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + node);

  size_t nr_subkeys_in_nk = le32toh (nk->nr_subkeys);

  INIT_OFFSET_LIST (children);
  INIT_OFFSET_LIST (blocks);

  /* Deal with the common "no subkeys" case quickly. */
  if (nr_subkeys_in_nk == 0)
    goto ok;

  /* Arbitrarily limit the number of subkeys we will ever deal with. */
  if (nr_subkeys_in_nk > HIVEX_MAX_SUBKEYS) {
    errno = ERANGE;
    goto error;
  }

  /* Preallocate space for the children. */
  if (grow_offset_list (&children, nr_subkeys_in_nk) == -1)
    goto error;

  /* The subkey_lf field can point either to an lf-record, which is
   * the common case, or if there are lots of subkeys, to an
   * ri-record.
   */
  size_t subkey_lf = le32toh (nk->subkey_lf);
  subkey_lf += 0x1000;
  if (!IS_VALID_BLOCK (h, subkey_lf)) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_children: returning EFAULT because subkey_lf is not a valid block (0x%zx)\n",
               subkey_lf);
    errno = EFAULT;
    goto error;
  }

  if (add_to_offset_list (&blocks, subkey_lf) == -1)
    goto error;

  struct ntreg_hbin_block *block =
    (struct ntreg_hbin_block *) (h->addr + subkey_lf);

  /* Points to lf-record?  (Note, also "lh" but that is basically the
   * same as "lf" as far as we are concerned here).
   */
  if (block->id[0] == 'l' && (block->id[1] == 'f' || block->id[1] == 'h')) {
    struct ntreg_lf_record *lf = (struct ntreg_lf_record *) block;

    /* Check number of subkeys in the nk-record matches number of subkeys
     * in the lf-record.
     */
    size_t nr_subkeys_in_lf = le16toh (lf->nr_keys);

    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_children: nr_subkeys_in_nk = %zu, nr_subkeys_in_lf = %zu\n",
               nr_subkeys_in_nk, nr_subkeys_in_lf);

    if (nr_subkeys_in_nk != nr_subkeys_in_lf) {
      errno = ENOTSUP;
      goto error;
    }

    size_t len = block_len (h, subkey_lf, NULL);
    if (8 + nr_subkeys_in_lf * 8 > len) {
      if (h->msglvl >= 2)
        fprintf (stderr, "hivex_node_children: returning EFAULT because too many subkeys (%zu, %zu)\n",
                 nr_subkeys_in_lf, len);
      errno = EFAULT;
      goto error;
    }

    size_t i;
    for (i = 0; i < nr_subkeys_in_lf; ++i) {
      hive_node_h subkey = le32toh (lf->keys[i].offset);
      subkey += 0x1000;
      if (!(flags & GET_CHILDREN_NO_CHECK_NK)) {
        if (!IS_VALID_BLOCK (h, subkey)) {
          if (h->msglvl >= 2)
            fprintf (stderr, "hivex_node_children: returning EFAULT because subkey is not a valid block (0x%zx)\n",
                     subkey);
          errno = EFAULT;
          goto error;
        }
      }
      if (add_to_offset_list (&children, subkey) == -1)
        goto error;
    }
    goto ok;
  }
  /* Points to ri-record? */
  else if (block->id[0] == 'r' && block->id[1] == 'i') {
    struct ntreg_ri_record *ri = (struct ntreg_ri_record *) block;

    size_t nr_offsets = le16toh (ri->nr_offsets);

    /* Count total number of children. */
    size_t i, count = 0;
    for (i = 0; i < nr_offsets; ++i) {
      hive_node_h offset = le32toh (ri->offset[i]);
      offset += 0x1000;
      if (!IS_VALID_BLOCK (h, offset)) {
        if (h->msglvl >= 2)
          fprintf (stderr, "hivex_node_children: returning EFAULT because ri-offset is not a valid block (0x%zx)\n",
                   offset);
        errno = EFAULT;
        goto error;
      }
      if (!BLOCK_ID_EQ (h, offset, "lf") && !BLOCK_ID_EQ (h, offset, "lh")) {
        if (h->msglvl >= 2)
          fprintf (stderr, "get_children: returning ENOTSUP because ri-record offset does not point to lf/lh (0x%zx)\n",
                   offset);
        errno = ENOTSUP;
        goto error;
      }

      if (add_to_offset_list (&blocks, offset) == -1)
        goto error;

      struct ntreg_lf_record *lf =
        (struct ntreg_lf_record *) (h->addr + offset);

      count += le16toh (lf->nr_keys);
    }

    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_children: nr_subkeys_in_nk = %zu, counted = %zu\n",
               nr_subkeys_in_nk, count);

    if (nr_subkeys_in_nk != count) {
      errno = ENOTSUP;
      goto error;
    }

    /* Copy list of children.  Note nr_subkeys_in_nk is limited to
     * something reasonable above.
     */
    for (i = 0; i < nr_offsets; ++i) {
      hive_node_h offset = le32toh (ri->offset[i]);
      offset += 0x1000;
      if (!IS_VALID_BLOCK (h, offset)) {
        if (h->msglvl >= 2)
          fprintf (stderr, "hivex_node_children: returning EFAULT because ri-offset is not a valid block (0x%zx)\n",
                   offset);
        errno = EFAULT;
        goto error;
      }
      if (!BLOCK_ID_EQ (h, offset, "lf") && !BLOCK_ID_EQ (h, offset, "lh")) {
        if (h->msglvl >= 2)
          fprintf (stderr, "get_children: returning ENOTSUP because ri-record offset does not point to lf/lh (0x%zx)\n",
                   offset);
        errno = ENOTSUP;
        goto error;
      }

      struct ntreg_lf_record *lf =
        (struct ntreg_lf_record *) (h->addr + offset);

      size_t j;
      for (j = 0; j < le16toh (lf->nr_keys); ++j) {
        hive_node_h subkey = le32toh (lf->keys[j].offset);
        subkey += 0x1000;
        if (!(flags & GET_CHILDREN_NO_CHECK_NK)) {
          if (!IS_VALID_BLOCK (h, subkey)) {
            if (h->msglvl >= 2)
              fprintf (stderr, "hivex_node_children: returning EFAULT because indirect subkey is not a valid block (0x%zx)\n",
                       subkey);
            errno = EFAULT;
            goto error;
          }
        }
        if (add_to_offset_list (&children, subkey) == -1)
          goto error;
      }
    }
    goto ok;
  }
  /* else not supported, set errno and fall through */
  if (h->msglvl >= 2)
    fprintf (stderr, "get_children: returning ENOTSUP because subkey block is not lf/lh/ri (0x%zx, %d, %d)\n",
             subkey_lf, block->id[0], block->id[1]);
  errno = ENOTSUP;
 error:
  free_offset_list (&children);
  free_offset_list (&blocks);
  return -1;

 ok:
  *children_ret = return_offset_list (&children);
  *blocks_ret = return_offset_list (&blocks);
  if (!*children_ret || !*blocks_ret)
    goto error;
  return 0;
}

hive_node_h *
hivex_node_children (hive_h *h, hive_node_h node)
{
  hive_node_h *children;
  size_t *blocks;

  if (get_children (h, node, &children, &blocks, 0) == -1)
    return NULL;

  free (blocks);
  return children;
}

/* Very inefficient, but at least having a separate API call
 * allows us to make it more efficient in future.
 */
hive_node_h
hivex_node_get_child (hive_h *h, hive_node_h node, const char *nname)
{
  hive_node_h *children = NULL;
  char *name = NULL;
  hive_node_h ret = 0;

  children = hivex_node_children (h, node);
  if (!children) goto error;

  size_t i;
  for (i = 0; children[i] != 0; ++i) {
    name = hivex_node_name (h, children[i]);
    if (!name) goto error;
    if (STRCASEEQ (name, nname)) {
      ret = children[i];
      break;
    }
    free (name); name = NULL;
  }

 error:
  free (children);
  free (name);
  return ret;
}

hive_node_h
hivex_node_parent (hive_h *h, hive_node_h node)
{
  if (!IS_VALID_BLOCK (h, node) || !BLOCK_ID_EQ (h, node, "nk")) {
    errno = EINVAL;
    return 0;
  }

  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + node);

  hive_node_h ret = le32toh (nk->parent);
  ret += 0x1000;
  if (!IS_VALID_BLOCK (h, ret)) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_parent: returning EFAULT because parent is not a valid block (0x%zx)\n",
              ret);
    errno = EFAULT;
    return 0;
  }
  return ret;
}

static int
get_values (hive_h *h, hive_node_h node,
            hive_value_h **values_ret, size_t **blocks_ret)
{
  if (!IS_VALID_BLOCK (h, node) || !BLOCK_ID_EQ (h, node, "nk")) {
    errno = EINVAL;
    return -1;
  }

  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + node);

  size_t nr_values = le32toh (nk->nr_values);

  if (h->msglvl >= 2)
    fprintf (stderr, "hivex_node_values: nr_values = %zu\n", nr_values);

  INIT_OFFSET_LIST (values);
  INIT_OFFSET_LIST (blocks);

  /* Deal with the common "no values" case quickly. */
  if (nr_values == 0)
    goto ok;

  /* Arbitrarily limit the number of values we will ever deal with. */
  if (nr_values > HIVEX_MAX_VALUES) {
    errno = ERANGE;
    goto error;
  }

  /* Preallocate space for the values. */
  if (grow_offset_list (&values, nr_values) == -1)
    goto error;

  /* Get the value list and check it looks reasonable. */
  size_t vlist_offset = le32toh (nk->vallist);
  vlist_offset += 0x1000;
  if (!IS_VALID_BLOCK (h, vlist_offset)) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_values: returning EFAULT because value list is not a valid block (0x%zx)\n",
               vlist_offset);
    errno = EFAULT;
    goto error;
  }

  if (add_to_offset_list (&blocks, vlist_offset) == -1)
    goto error;

  struct ntreg_value_list *vlist =
    (struct ntreg_value_list *) (h->addr + vlist_offset);

  size_t len = block_len (h, vlist_offset, NULL);
  if (4 + nr_values * 4 > len) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_values: returning EFAULT because value list is too long (%zu, %zu)\n",
               nr_values, len);
    errno = EFAULT;
    goto error;
  }

  size_t i;
  for (i = 0; i < nr_values; ++i) {
    hive_node_h value = vlist->offset[i];
    value += 0x1000;
    if (!IS_VALID_BLOCK (h, value)) {
      if (h->msglvl >= 2)
        fprintf (stderr, "hivex_node_values: returning EFAULT because value is not a valid block (0x%zx)\n",
                 value);
      errno = EFAULT;
      goto error;
    }
    if (add_to_offset_list (&values, value) == -1)
      goto error;
  }

 ok:
  *values_ret = return_offset_list (&values);
  *blocks_ret = return_offset_list (&blocks);
  if (!*values_ret || !*blocks_ret)
    goto error;
  return 0;

 error:
  free_offset_list (&values);
  free_offset_list (&blocks);
  return -1;
}

hive_value_h *
hivex_node_values (hive_h *h, hive_node_h node)
{
  hive_value_h *values;
  size_t *blocks;

  if (get_values (h, node, &values, &blocks) == -1)
    return NULL;

  free (blocks);
  return values;
}

/* Very inefficient, but at least having a separate API call
 * allows us to make it more efficient in future.
 */
hive_value_h
hivex_node_get_value (hive_h *h, hive_node_h node, const char *key)
{
  hive_value_h *values = NULL;
  char *name = NULL;
  hive_value_h ret = 0;

  values = hivex_node_values (h, node);
  if (!values) goto error;

  size_t i;
  for (i = 0; values[i] != 0; ++i) {
    name = hivex_value_key (h, values[i]);
    if (!name) goto error;
    if (STRCASEEQ (name, key)) {
      ret = values[i];
      break;
    }
    free (name); name = NULL;
  }

 error:
  free (values);
  free (name);
  return ret;
}

char *
hivex_value_key (hive_h *h, hive_value_h value)
{
  if (!IS_VALID_BLOCK (h, value) || !BLOCK_ID_EQ (h, value, "vk")) {
    errno = EINVAL;
    return 0;
  }

  struct ntreg_vk_record *vk = (struct ntreg_vk_record *) (h->addr + value);

  /* AFAIK the key is always plain ASCII, so no conversion to UTF-8 is
   * necessary.  However we do need to nul-terminate the string.
   */

  /* vk->name_len is unsigned, 16 bit, so this is safe ...  However
   * we have to make sure the length doesn't exceed the block length.
   */
  size_t len = le16toh (vk->name_len);
  size_t seg_len = block_len (h, value, NULL);
  if (sizeof (struct ntreg_vk_record) + len - 1 > seg_len) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_value_key: returning EFAULT because key length is too long (%zu, %zu)\n",
               len, seg_len);
    errno = EFAULT;
    return NULL;
  }

  char *ret = malloc (len + 1);
  if (ret == NULL)
    return NULL;
  memcpy (ret, vk->name, len);
  ret[len] = '\0';
  return ret;
}

int
hivex_value_type (hive_h *h, hive_value_h value, hive_type *t, size_t *len)
{
  if (!IS_VALID_BLOCK (h, value) || !BLOCK_ID_EQ (h, value, "vk")) {
    errno = EINVAL;
    return -1;
  }

  struct ntreg_vk_record *vk = (struct ntreg_vk_record *) (h->addr + value);

  if (t)
    *t = le32toh (vk->data_type);

  if (len) {
    *len = le32toh (vk->data_len);
    *len &= 0x7fffffff;         /* top bit indicates if data is stored inline */
  }

  return 0;
}

char *
hivex_value_value (hive_h *h, hive_value_h value,
                   hive_type *t_rtn, size_t *len_rtn)
{
  if (!IS_VALID_BLOCK (h, value) || !BLOCK_ID_EQ (h, value, "vk")) {
    errno = EINVAL;
    return NULL;
  }

  struct ntreg_vk_record *vk = (struct ntreg_vk_record *) (h->addr + value);

  hive_type t;
  size_t len;
  int is_inline;

  t = le32toh (vk->data_type);

  len = le32toh (vk->data_len);
  is_inline = !!(len & 0x80000000);
  len &= 0x7fffffff;

  if (h->msglvl >= 2)
    fprintf (stderr, "hivex_value_value: value=0x%zx, t=%d, len=%zu, inline=%d\n",
             value, t, len, is_inline);

  if (t_rtn)
    *t_rtn = t;
  if (len_rtn)
    *len_rtn = len;

  if (is_inline && len > 4) {
    errno = ENOTSUP;
    return NULL;
  }

  /* Arbitrarily limit the length that we will read. */
  if (len > HIVEX_MAX_VALUE_LEN) {
    errno = ERANGE;
    return NULL;
  }

  char *ret = malloc (len);
  if (ret == NULL)
    return NULL;

  if (is_inline) {
    memcpy (ret, (char *) &vk->data_offset, len);
    return ret;
  }

  size_t data_offset = le32toh (vk->data_offset);
  data_offset += 0x1000;
  if (!IS_VALID_BLOCK (h, data_offset)) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_value_value: returning EFAULT because data offset is not a valid block (0x%zx)\n",
               data_offset);
    errno = EFAULT;
    free (ret);
    return NULL;
  }

  /* Check that the declared size isn't larger than the block its in.
   *
   * XXX Some apparently valid registries are seen to have this,
   * so turn this into a warning and substitute the smaller length
   * instead.
   */
  size_t blen = block_len (h, data_offset, NULL);
  if (len > blen - 4 /* subtract 4 for block header */) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_value_value: warning: declared data length is longer than the block it is in (data 0x%zx, data len %zu, block len %zu)\n",
               data_offset, len, blen);
    len = blen - 4;
  }

  char *data = h->addr + data_offset + 4;
  memcpy (ret, data, len);
  return ret;
}

static char *
windows_utf16_to_utf8 (/* const */ char *input, size_t len)
{
  iconv_t ic = iconv_open ("UTF-8", "UTF-16");
  if (ic == (iconv_t) -1)
    return NULL;

  /* iconv(3) has an insane interface ... */

  /* Mostly UTF-8 will be smaller, so this is a good initial guess. */
  size_t outalloc = len;

 again:;
  size_t inlen = len;
  size_t outlen = outalloc;
  char *out = malloc (outlen + 1);
  if (out == NULL) {
    int err = errno;
    iconv_close (ic);
    errno = err;
    return NULL;
  }
  char *inp = input;
  char *outp = out;

  size_t r = iconv (ic, &inp, &inlen, &outp, &outlen);
  if (r == (size_t) -1) {
    if (errno == E2BIG) {
      size_t prev = outalloc;
      /* Try again with a larger output buffer. */
      free (out);
      outalloc *= 2;
      if (outalloc < prev)
        return NULL;
      goto again;
    }
    else {
      /* Else some conversion failure, eg. EILSEQ, EINVAL. */
      int err = errno;
      iconv_close (ic);
      free (out);
      errno = err;
      return NULL;
    }
  }

  *outp = '\0';
  iconv_close (ic);

  return out;
}

char *
hivex_value_string (hive_h *h, hive_value_h value)
{
  hive_type t;
  size_t len;
  char *data = hivex_value_value (h, value, &t, &len);

  if (data == NULL)
    return NULL;

  if (t != hive_t_string && t != hive_t_expand_string && t != hive_t_link) {
    free (data);
    errno = EINVAL;
    return NULL;
  }

  char *ret = windows_utf16_to_utf8 (data, len);
  free (data);
  if (ret == NULL)
    return NULL;

  return ret;
}

static void
free_strings (char **argv)
{
  if (argv) {
    size_t i;

    for (i = 0; argv[i] != NULL; ++i)
      free (argv[i]);
    free (argv);
  }
}

/* Get the length of a UTF-16 format string.  Handle the string as
 * pairs of bytes, looking for the first \0\0 pair.
 */
static size_t
utf16_string_len_in_bytes (const char *str)
{
  size_t ret = 0;

  while (str[0] || str[1]) {
    str += 2;
    ret += 2;
  }

  return ret;
}

/* http://blogs.msdn.com/oldnewthing/archive/2009/10/08/9904646.aspx */
char **
hivex_value_multiple_strings (hive_h *h, hive_value_h value)
{
  hive_type t;
  size_t len;
  char *data = hivex_value_value (h, value, &t, &len);

  if (data == NULL)
    return NULL;

  if (t != hive_t_multiple_strings) {
    free (data);
    errno = EINVAL;
    return NULL;
  }

  size_t nr_strings = 0;
  char **ret = malloc ((1 + nr_strings) * sizeof (char *));
  if (ret == NULL) {
    free (data);
    return NULL;
  }
  ret[0] = NULL;

  char *p = data;
  size_t plen;

  while (p < data + len && (plen = utf16_string_len_in_bytes (p)) > 0) {
    nr_strings++;
    char **ret2 = realloc (ret, (1 + nr_strings) * sizeof (char *));
    if (ret2 == NULL) {
      free_strings (ret);
      free (data);
      return NULL;
    }
    ret = ret2;

    ret[nr_strings-1] = windows_utf16_to_utf8 (p, plen);
    ret[nr_strings] = NULL;
    if (ret[nr_strings-1] == NULL) {
      free_strings (ret);
      free (data);
      return NULL;
    }

    p += plen + 2 /* skip over UTF-16 \0\0 at the end of this string */;
  }

  free (data);
  return ret;
}

int32_t
hivex_value_dword (hive_h *h, hive_value_h value)
{
  hive_type t;
  size_t len;
  char *data = hivex_value_value (h, value, &t, &len);

  if (data == NULL)
    return -1;

  if ((t != hive_t_dword && t != hive_t_dword_be) || len != 4) {
    free (data);
    errno = EINVAL;
    return -1;
  }

  int32_t ret = *(int32_t*)data;
  free (data);
  if (t == hive_t_dword)        /* little endian */
    ret = le32toh (ret);
  else
    ret = be32toh (ret);

  return ret;
}

int64_t
hivex_value_qword (hive_h *h, hive_value_h value)
{
  hive_type t;
  size_t len;
  char *data = hivex_value_value (h, value, &t, &len);

  if (data == NULL)
    return -1;

  if (t != hive_t_qword || len != 8) {
    free (data);
    errno = EINVAL;
    return -1;
  }

  int64_t ret = *(int64_t*)data;
  free (data);
  ret = le64toh (ret);          /* always little endian */

  return ret;
}

/*----------------------------------------------------------------------
 * Visiting.
 */

int
hivex_visit (hive_h *h, const struct hivex_visitor *visitor, size_t len,
             void *opaque, int flags)
{
  return hivex_visit_node (h, hivex_root (h), visitor, len, opaque, flags);
}

static int hivex__visit_node (hive_h *h, hive_node_h node, const struct hivex_visitor *vtor, char *unvisited, void *opaque, int flags);

int
hivex_visit_node (hive_h *h, hive_node_h node,
                  const struct hivex_visitor *visitor, size_t len, void *opaque,
                  int flags)
{
  struct hivex_visitor vtor;
  memset (&vtor, 0, sizeof vtor);

  /* Note that len might be larger *or smaller* than the expected size. */
  size_t copysize = len <= sizeof vtor ? len : sizeof vtor;
  memcpy (&vtor, visitor, copysize);

  /* This bitmap records unvisited nodes, so we don't loop if the
   * registry contains cycles.
   */
  char *unvisited = malloc (1 + h->size / 32);
  if (unvisited == NULL)
    return -1;
  memcpy (unvisited, h->bitmap, 1 + h->size / 32);

  int r = hivex__visit_node (h, node, &vtor, unvisited, opaque, flags);
  free (unvisited);
  return r;
}

static int
hivex__visit_node (hive_h *h, hive_node_h node,
                   const struct hivex_visitor *vtor, char *unvisited,
                   void *opaque, int flags)
{
  int skip_bad = flags & HIVEX_VISIT_SKIP_BAD;
  char *name = NULL;
  hive_value_h *values = NULL;
  hive_node_h *children = NULL;
  char *key = NULL;
  char *str = NULL;
  char **strs = NULL;
  int i;

  /* Return -1 on all callback errors.  However on internal errors,
   * check if skip_bad is set and suppress those errors if so.
   */
  int ret = -1;

  if (!BITMAP_TST (unvisited, node)) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex__visit_node: contains cycle: visited node 0x%zx already\n",
               node);

    errno = ELOOP;
    return skip_bad ? 0 : -1;
  }
  BITMAP_CLR (unvisited, node);

  name = hivex_node_name (h, node);
  if (!name) return skip_bad ? 0 : -1;
  if (vtor->node_start && vtor->node_start (h, opaque, node, name) == -1)
    goto error;

  values = hivex_node_values (h, node);
  if (!values) {
    ret = skip_bad ? 0 : -1;
    goto error;
  }

  for (i = 0; values[i] != 0; ++i) {
    hive_type t;
    size_t len;

    if (hivex_value_type (h, values[i], &t, &len) == -1) {
      ret = skip_bad ? 0 : -1;
      goto error;
    }

    key = hivex_value_key (h, values[i]);
    if (key == NULL) {
      ret = skip_bad ? 0 : -1;
      goto error;
    }

    if (vtor->value_any) {
      str = hivex_value_value (h, values[i], &t, &len);
      if (str == NULL) {
        ret = skip_bad ? 0 : -1;
        goto error;
      }
      if (vtor->value_any (h, opaque, node, values[i], t, len, key, str) == -1)
        goto error;
      free (str); str = NULL;
    }
    else {
      switch (t) {
      case hive_t_none:
        str = hivex_value_value (h, values[i], &t, &len);
        if (str == NULL) {
          ret = skip_bad ? 0 : -1;
          goto error;
        }
        if (t != hive_t_none) {
          ret = skip_bad ? 0 : -1;
          goto error;
        }
        if (vtor->value_none &&
            vtor->value_none (h, opaque, node, values[i], t, len, key, str) == -1)
          goto error;
        free (str); str = NULL;
        break;

      case hive_t_string:
      case hive_t_expand_string:
      case hive_t_link:
        str = hivex_value_string (h, values[i]);
        if (str == NULL) {
          if (errno != EILSEQ && errno != EINVAL) {
            ret = skip_bad ? 0 : -1;
            goto error;
          }
          if (vtor->value_string_invalid_utf16) {
            str = hivex_value_value (h, values[i], &t, &len);
            if (vtor->value_string_invalid_utf16 (h, opaque, node, values[i], t, len, key, str) == -1)
              goto error;
            free (str); str = NULL;
          }
          break;
        }
        if (vtor->value_string &&
            vtor->value_string (h, opaque, node, values[i], t, len, key, str) == -1)
          goto error;
        free (str); str = NULL;
        break;

      case hive_t_dword:
      case hive_t_dword_be: {
        int32_t i32 = hivex_value_dword (h, values[i]);
        if (vtor->value_dword &&
            vtor->value_dword (h, opaque, node, values[i], t, len, key, i32) == -1)
          goto error;
        break;
      }

      case hive_t_qword: {
        int64_t i64 = hivex_value_qword (h, values[i]);
        if (vtor->value_qword &&
            vtor->value_qword (h, opaque, node, values[i], t, len, key, i64) == -1)
          goto error;
        break;
      }

      case hive_t_binary:
        str = hivex_value_value (h, values[i], &t, &len);
        if (str == NULL) {
          ret = skip_bad ? 0 : -1;
          goto error;
        }
        if (t != hive_t_binary) {
          ret = skip_bad ? 0 : -1;
          goto error;
        }
        if (vtor->value_binary &&
            vtor->value_binary (h, opaque, node, values[i], t, len, key, str) == -1)
          goto error;
        free (str); str = NULL;
        break;

      case hive_t_multiple_strings:
        strs = hivex_value_multiple_strings (h, values[i]);
        if (strs == NULL) {
          if (errno != EILSEQ && errno != EINVAL) {
            ret = skip_bad ? 0 : -1;
            goto error;
          }
          if (vtor->value_string_invalid_utf16) {
            str = hivex_value_value (h, values[i], &t, &len);
            if (vtor->value_string_invalid_utf16 (h, opaque, node, values[i], t, len, key, str) == -1)
              goto error;
            free (str); str = NULL;
          }
          break;
        }
        if (vtor->value_multiple_strings &&
            vtor->value_multiple_strings (h, opaque, node, values[i], t, len, key, strs) == -1)
          goto error;
        free_strings (strs); strs = NULL;
        break;

      case hive_t_resource_list:
      case hive_t_full_resource_description:
      case hive_t_resource_requirements_list:
      default:
        str = hivex_value_value (h, values[i], &t, &len);
        if (str == NULL) {
          ret = skip_bad ? 0 : -1;
          goto error;
        }
        if (vtor->value_other &&
            vtor->value_other (h, opaque, node, values[i], t, len, key, str) == -1)
          goto error;
        free (str); str = NULL;
        break;
      }
    }

    free (key); key = NULL;
  }

  children = hivex_node_children (h, node);
  if (children == NULL) {
    ret = skip_bad ? 0 : -1;
    goto error;
  }

  for (i = 0; children[i] != 0; ++i) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex__visit_node: %s: visiting subkey %d (0x%zx)\n",
               name, i, children[i]);

    if (hivex__visit_node (h, children[i], vtor, unvisited, opaque, flags) == -1)
      goto error;
  }

  if (vtor->node_end && vtor->node_end (h, opaque, node, name) == -1)
    goto error;

  ret = 0;

 error:
  free (name);
  free (values);
  free (children);
  free (key);
  free (str);
  free_strings (strs);
  return ret;
}

/*----------------------------------------------------------------------
 * Writing.
 */

/* Allocate an hbin (page), extending the malloc'd space if necessary,
 * and updating the hive handle fields (but NOT the hive disk header
 * -- the hive disk header is updated when we commit).  This function
 * also extends the bitmap if necessary.
 *
 * 'allocation_hint' is the size of the block allocation we would like
 * to make.  Normally registry blocks are very small (avg 50 bytes)
 * and are contained in standard-sized pages (4KB), but the registry
 * can support blocks which are larger than a standard page, in which
 * case it creates a page of 8KB, 12KB etc.
 *
 * Returns:
 * > 0 : offset of first usable byte of new page (after page header)
 * 0   : error (errno set)
 */
static size_t
allocate_page (hive_h *h, size_t allocation_hint)
{
  /* In almost all cases this will be 1. */
  size_t nr_4k_pages =
    1 + (allocation_hint + sizeof (struct ntreg_hbin_page) - 1) / 4096;
  assert (nr_4k_pages >= 1);

  /* 'extend' is the number of bytes to extend the file by.  Note that
   * hives found in the wild often contain slack between 'endpages'
   * and the actual end of the file, so we don't always need to make
   * the file larger.
   */
  ssize_t extend = h->endpages + nr_4k_pages * 4096 - h->size;

  if (h->msglvl >= 2) {
    fprintf (stderr, "allocate_page: current endpages = 0x%zx, current size = 0x%zx\n",
             h->endpages, h->size);
    fprintf (stderr, "allocate_page: extending file by %zd bytes (<= 0 if no extension)\n",
             extend);
  }

  if (extend > 0) {
    size_t oldsize = h->size;
    size_t newsize = h->size + extend;
    char *newaddr = realloc (h->addr, newsize);
    if (newaddr == NULL)
      return 0;

    size_t oldbitmapsize = 1 + oldsize / 32;
    size_t newbitmapsize = 1 + newsize / 32;
    char *newbitmap = realloc (h->bitmap, newbitmapsize);
    if (newbitmap == NULL) {
      free (newaddr);
      return 0;
    }

    h->addr = newaddr;
    h->size = newsize;
    h->bitmap = newbitmap;

    memset (h->addr + oldsize, 0, newsize - oldsize);
    memset (h->bitmap + oldbitmapsize, 0, newbitmapsize - oldbitmapsize);
  }

  size_t offset = h->endpages;
  h->endpages += nr_4k_pages * 4096;

  if (h->msglvl >= 2)
    fprintf (stderr, "allocate_page: new endpages = 0x%zx, new size = 0x%zx\n",
             h->endpages, h->size);

  /* Write the hbin header. */
  struct ntreg_hbin_page *page =
    (struct ntreg_hbin_page *) (h->addr + offset);
  page->magic[0] = 'h';
  page->magic[1] = 'b';
  page->magic[2] = 'i';
  page->magic[3] = 'n';
  page->offset_first = htole32 (offset - 0x1000);
  page->page_size = htole32 (nr_4k_pages * 4096);
  memset (page->unknown, 0, sizeof (page->unknown));

  if (h->msglvl >= 2)
    fprintf (stderr, "allocate_page: new page at 0x%zx\n", offset);

  /* Offset of first usable byte after the header. */
  return offset + sizeof (struct ntreg_hbin_page);
}

/* Allocate a single block, first allocating an hbin (page) at the end
 * of the current file if necessary.  NB. To keep the implementation
 * simple and more likely to be correct, we do not reuse existing free
 * blocks.
 *
 * seg_len is the size of the block (this INCLUDES the block header).
 * The header of the block is initialized to -seg_len (negative to
 * indicate used).  id[2] is the block ID (type), eg. "nk" for nk-
 * record.  The block bitmap is updated to show this block as valid.
 * The rest of the contents of the block will be zero.
 *
 * Returns:
 * > 0 : offset of new block
 * 0   : error (errno set)
 */
static size_t
allocate_block (hive_h *h, size_t seg_len, const char id[2])
{
  if (!h->writable) {
    errno = EROFS;
    return 0;
  }

  if (seg_len < 4) {
    /* The caller probably forgot to include the header.  Note that
     * value lists have no ID field, so seg_len == 4 would be possible
     * for them, albeit unusual.
     */
    if (h->msglvl >= 2)
      fprintf (stderr, "allocate_block: refusing too small allocation (%zu), returning ERANGE\n",
               seg_len);
    errno = ERANGE;
    return 0;
  }

  /* Refuse really large allocations. */
  if (seg_len > HIVEX_MAX_ALLOCATION) {
    if (h->msglvl >= 2)
      fprintf (stderr, "allocate_block: refusing large allocation (%zu), returning ERANGE\n",
               seg_len);
    errno = ERANGE;
    return 0;
  }

  /* Round up allocation to multiple of 8 bytes.  All blocks must be
   * on an 8 byte boundary.
   */
  seg_len = (seg_len + 7) & ~7;

  /* Allocate a new page if necessary. */
  if (h->endblocks == 0 || h->endblocks + seg_len > h->endpages) {
    size_t newendblocks = allocate_page (h, seg_len);
    if (newendblocks == 0)
      return 0;
    h->endblocks = newendblocks;
  }

  size_t offset = h->endblocks;

  if (h->msglvl >= 2)
    fprintf (stderr, "allocate_block: new block at 0x%zx, size %zu\n",
             offset, seg_len);

  struct ntreg_hbin_block *blockhdr =
    (struct ntreg_hbin_block *) (h->addr + offset);

  blockhdr->seg_len = htole32 (- (int32_t) seg_len);
  if (id[0] && id[1] && seg_len >= sizeof (struct ntreg_hbin_block)) {
    blockhdr->id[0] = id[0];
    blockhdr->id[1] = id[1];
  }

  BITMAP_SET (h->bitmap, offset);

  h->endblocks += seg_len;

  /* If there is space after the last block in the last page, then we
   * have to put a dummy free block header here to mark the rest of
   * the page as free.
   */
  ssize_t rem = h->endpages - h->endblocks;
  if (rem > 0) {
    if (h->msglvl >= 2)
      fprintf (stderr, "allocate_block: marking remainder of page free starting at 0x%zx, size %zd\n",
               h->endblocks, rem);

    assert (rem >= 4);

    blockhdr = (struct ntreg_hbin_block *) (h->addr + h->endblocks);
    blockhdr->seg_len = htole32 ((int32_t) rem);
  }

  return offset;
}

/* 'offset' must point to a valid, used block.  This function marks
 * the block unused (by updating the seg_len field) and invalidates
 * the bitmap.  It does NOT do this recursively, so to avoid creating
 * unreachable used blocks, callers may have to recurse over the hive
 * structures.  Also callers must ensure there are no references to
 * this block from other parts of the hive.
 */
static void
mark_block_unused (hive_h *h, size_t offset)
{
  assert (h->writable);
  assert (IS_VALID_BLOCK (h, offset));

  if (h->msglvl >= 2)
    fprintf (stderr, "mark_block_unused: marking 0x%zx unused\n", offset);

  struct ntreg_hbin_block *blockhdr =
    (struct ntreg_hbin_block *) (h->addr + offset);

  size_t seg_len = block_len (h, offset, NULL);
  blockhdr->seg_len = htole32 (seg_len);

  BITMAP_CLR (h->bitmap, offset);
}

/* Delete all existing values at this node. */
static int
delete_values (hive_h *h, hive_node_h node)
{
  assert (h->writable);

  hive_value_h *values;
  size_t *blocks;
  if (get_values (h, node, &values, &blocks) == -1)
    return -1;

  size_t i;
  for (i = 0; blocks[i] != 0; ++i)
    mark_block_unused (h, blocks[i]);

  free (blocks);

  for (i = 0; values[i] != 0; ++i) {
    struct ntreg_vk_record *vk =
      (struct ntreg_vk_record *) (h->addr + values[i]);

    size_t len;
    int is_inline;
    len = le32toh (vk->data_len);
    is_inline = !!(len & 0x80000000); /* top bit indicates is inline */
    len &= 0x7fffffff;

    if (!is_inline) {           /* non-inline, so remove data block */
      size_t data_offset = le32toh (vk->data_offset);
      data_offset += 0x1000;
      mark_block_unused (h, data_offset);
    }

    /* remove vk record */
    mark_block_unused (h, values[i]);
  }

  free (values);

  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + node);
  nk->nr_values = htole32 (0);
  nk->vallist = htole32 (0xffffffff);

  return 0;
}

int
hivex_commit (hive_h *h, const char *filename, int flags)
{
  if (flags != 0) {
    errno = EINVAL;
    return -1;
  }

  if (!h->writable) {
    errno = EROFS;
    return -1;
  }

  filename = filename ? : h->filename;
  int fd = open (filename, O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY, 0666);
  if (fd == -1)
    return -1;

  /* Update the header fields. */
  uint32_t sequence = le32toh (h->hdr->sequence1);
  sequence++;
  h->hdr->sequence1 = htole32 (sequence);
  h->hdr->sequence2 = htole32 (sequence);
  /* XXX Ought to update h->hdr->last_modified. */
  h->hdr->blocks = htole32 (h->endpages - 0x1000);

  /* Recompute header checksum. */
  uint32_t sum = header_checksum (h);
  h->hdr->csum = htole32 (sum);

  if (h->msglvl >= 2)
    fprintf (stderr, "hivex_commit: new header checksum: 0x%x\n", sum);

  if (full_write (fd, h->addr, h->size) != h->size) {
    int err = errno;
    close (fd);
    errno = err;
    return -1;
  }

  if (close (fd) == -1)
    return -1;

  return 0;
}

/* Calculate the hash for a lf or lh record offset.
 */
static void
calc_hash (const char *type, const char *name, char *ret)
{
  size_t len = strlen (name);

  if (STRPREFIX (type, "lf"))
    /* Old-style, not used in current registries. */
    memcpy (ret, name, len < 4 ? len : 4);
  else {
    /* New-style for lh-records. */
    size_t i, c;
    uint32_t h = 0;
    for (i = 0; i < len; ++i) {
      c = c_toupper (name[i]);
      h *= 37;
      h += c;
    }
    *((uint32_t *) ret) = htole32 (h);
  }
}

/* Create a completely new lh-record containing just the single node. */
static size_t
new_lh_record (hive_h *h, const char *name, hive_node_h node)
{
  static const char id[2] = { 'l', 'h' };
  size_t seg_len = sizeof (struct ntreg_lf_record);
  size_t offset = allocate_block (h, seg_len, id);
  if (offset == 0)
    return 0;

  struct ntreg_lf_record *lh = (struct ntreg_lf_record *) (h->addr + offset);
  lh->nr_keys = htole16 (1);
  lh->keys[0].offset = htole32 (node - 0x1000);
  calc_hash ("lh", name, lh->keys[0].hash);

  return offset;
}

/* Insert node into existing lf/lh-record at position.
 * This allocates a new record and marks the old one as unused.
 */
static size_t
insert_lf_record (hive_h *h, size_t old_offs, size_t posn,
                  const char *name, hive_node_h node)
{
  assert (IS_VALID_BLOCK (h, old_offs));

  /* Work around C stupidity.
   * http://www.redhat.com/archives/libguestfs/2010-February/msg00056.html
   */
  int test = BLOCK_ID_EQ (h, old_offs, "lf") || BLOCK_ID_EQ (h, old_offs, "lh");
  assert (test);

  struct ntreg_lf_record *old_lf =
    (struct ntreg_lf_record *) (h->addr + old_offs);
  size_t nr_keys = le16toh (old_lf->nr_keys);

  nr_keys++; /* in new record ... */

  size_t seg_len = sizeof (struct ntreg_lf_record) + (nr_keys-1) * 8;
  size_t new_offs = allocate_block (h, seg_len, old_lf->id);
  if (new_offs == 0)
    return 0;

  struct ntreg_lf_record *new_lf =
    (struct ntreg_lf_record *) (h->addr + new_offs);
  new_lf->nr_keys = htole16 (nr_keys);

  /* Copy the keys until we reach posn, insert the new key there, then
   * copy the remaining keys.
   */
  size_t i;
  for (i = 0; i < posn; ++i)
    new_lf->keys[i] = old_lf->keys[i];

  new_lf->keys[i].offset = htole32 (node - 0x1000);
  calc_hash (new_lf->id, name, new_lf->keys[i].hash);

  for (i = posn+1; i < nr_keys; ++i)
    new_lf->keys[i] = old_lf->keys[i-1];

  /* Old block is unused, return new block. */
  mark_block_unused (h, old_offs);
  return new_offs;
}

/* Compare name with name in nk-record. */
static int
compare_name_with_nk_name (hive_h *h, const char *name, hive_node_h nk_offs)
{
  assert (IS_VALID_BLOCK (h, nk_offs));
  assert (BLOCK_ID_EQ (h, nk_offs, "nk"));

  /* Name in nk is not necessarily nul-terminated. */
  char *nname = hivex_node_name (h, nk_offs);

  /* Unfortunately we don't have a way to return errors here. */
  if (!nname) {
    perror ("compare_name_with_nk_name");
    return 0;
  }

  int r = strcasecmp (name, nname);
  free (nname);

  return r;
}

hive_node_h
hivex_node_add_child (hive_h *h, hive_node_h parent, const char *name)
{
  if (!h->writable) {
    errno = EROFS;
    return 0;
  }

  if (!IS_VALID_BLOCK (h, parent) || !BLOCK_ID_EQ (h, parent, "nk")) {
    errno = EINVAL;
    return 0;
  }

  if (name == NULL || strlen (name) == 0) {
    errno = EINVAL;
    return 0;
  }

  if (hivex_node_get_child (h, parent, name) != 0) {
    errno = EEXIST;
    return 0;
  }

  /* Create the new nk-record. */
  static const char nk_id[2] = { 'n', 'k' };
  size_t seg_len = sizeof (struct ntreg_nk_record) + strlen (name);
  hive_node_h node = allocate_block (h, seg_len, nk_id);
  if (node == 0)
    return 0;

  if (h->msglvl >= 2)
    fprintf (stderr, "hivex_node_add_child: allocated new nk-record for child at 0x%zx\n", node);

  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + node);
  nk->flags = htole16 (0x0020); /* key is ASCII. */
  nk->parent = htole32 (parent - 0x1000);
  nk->subkey_lf = htole32 (0xffffffff);
  nk->subkey_lf_volatile = htole32 (0xffffffff);
  nk->vallist = htole32 (0xffffffff);
  nk->classname = htole32 (0xffffffff);
  nk->name_len = htole16 (strlen (name));
  strcpy (nk->name, name);

  /* Inherit parent sk. */
  struct ntreg_nk_record *parent_nk =
    (struct ntreg_nk_record *) (h->addr + parent);
  size_t parent_sk_offset = le32toh (parent_nk->sk);
  parent_sk_offset += 0x1000;
  if (!IS_VALID_BLOCK (h, parent_sk_offset) ||
      !BLOCK_ID_EQ (h, parent_sk_offset, "sk")) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_add_child: returning EFAULT because parent sk is not a valid block (%zu)\n",
               parent_sk_offset);
    errno = EFAULT;
    return 0;
  }
  struct ntreg_sk_record *sk =
    (struct ntreg_sk_record *) (h->addr + parent_sk_offset);
  sk->refcount = htole32 (le32toh (sk->refcount) + 1);
  nk->sk = htole32 (parent_sk_offset - 0x1000);

  /* Inherit parent timestamp. */
  memcpy (nk->timestamp, parent_nk->timestamp, sizeof (parent_nk->timestamp));

  /* What I found out the hard way (not documented anywhere): the
   * subkeys in lh-records must be kept sorted.  If you just add a
   * subkey in a non-sorted position (eg. just add it at the end) then
   * Windows won't see the subkey _and_ Windows will corrupt the hive
   * itself when it modifies or saves it.
   *
   * So use get_children() to get a list of intermediate
   * lf/lh-records.  get_children() returns these in reading order
   * (which is sorted), so we look for the lf/lh-records in sequence
   * until we find the key name just after the one we are inserting,
   * and we insert the subkey just before it.
   *
   * The only other case is the no-subkeys case, where we have to
   * create a brand new lh-record.
   */
  hive_node_h *unused;
  size_t *blocks;

  if (get_children (h, parent, &unused, &blocks, 0) == -1)
    return 0;
  free (unused);

  size_t i, j;
  size_t nr_subkeys_in_parent_nk = le32toh (parent_nk->nr_subkeys);
  if (nr_subkeys_in_parent_nk == 0) { /* No subkeys case. */
    /* Free up any existing intermediate blocks. */
    for (i = 0; blocks[i] != 0; ++i)
      mark_block_unused (h, blocks[i]);
    size_t lh_offs = new_lh_record (h, name, node);
    if (lh_offs == 0) {
      free (blocks);
      return 0;
    }

    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_add_child: no keys, allocated new lh-record at 0x%zx\n", lh_offs);

    parent_nk->subkey_lf = htole32 (lh_offs - 0x1000);
  }
  else {                        /* Insert subkeys case. */
    size_t old_offs = 0, new_offs = 0;
    struct ntreg_lf_record *old_lf = NULL;

    /* Find lf/lh key name just after the one we are inserting. */
    for (i = 0; blocks[i] != 0; ++i) {
      if (BLOCK_ID_EQ (h, blocks[i], "lf") ||
          BLOCK_ID_EQ (h, blocks[i], "lh")) {
        old_offs = blocks[i];
        old_lf = (struct ntreg_lf_record *) (h->addr + old_offs);
        for (j = 0; j < le16toh (old_lf->nr_keys); ++j) {
          hive_node_h nk_offs = le32toh (old_lf->keys[j].offset);
          nk_offs += 0x1000;
          if (compare_name_with_nk_name (h, name, nk_offs) < 0)
            goto insert_it;
        }
      }
    }

    /* Insert it at the end.
     * old_offs points to the last lf record, set j.
     */
    assert (old_offs != 0);   /* should never happen if nr_subkeys > 0 */
    j = le16toh (old_lf->nr_keys);

    /* Insert it. */
  insert_it:
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_add_child: insert key in existing lh-record at 0x%zx, posn %zu\n", old_offs, j);

    new_offs = insert_lf_record (h, old_offs, j, name, node);
    if (new_offs == 0) {
      free (blocks);
      return 0;
    }

    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_add_child: new lh-record at 0x%zx\n",
               new_offs);

    /* If the lf/lh-record was directly referenced by the parent nk,
     * then update the parent nk.
     */
    if (le32toh (parent_nk->subkey_lf) + 0x1000 == old_offs)
      parent_nk->subkey_lf = htole32 (new_offs - 0x1000);
    /* Else we have to look for the intermediate ri-record and update
     * that in-place.
     */
    else {
      for (i = 0; blocks[i] != 0; ++i) {
        if (BLOCK_ID_EQ (h, blocks[i], "ri")) {
          struct ntreg_ri_record *ri =
            (struct ntreg_ri_record *) (h->addr + blocks[i]);
          for (j = 0; j < le16toh (ri->nr_offsets); ++j)
            if (le32toh (ri->offset[j] + 0x1000) == old_offs) {
              ri->offset[j] = htole32 (new_offs - 0x1000);
              goto found_it;
            }
        }
      }

      /* Not found ..  This is an internal error. */
      if (h->msglvl >= 2)
        fprintf (stderr, "hivex_node_add_child: returning ENOTSUP because could not find ri->lf link\n");
      errno = ENOTSUP;
      free (blocks);
      return 0;

    found_it:
      ;
    }
  }

  free (blocks);

  /* Update nr_subkeys in parent nk. */
  nr_subkeys_in_parent_nk++;
  parent_nk->nr_subkeys = htole32 (nr_subkeys_in_parent_nk);

  /* Update max_subkey_name_len in parent nk. */
  uint16_t max = le16toh (parent_nk->max_subkey_name_len);
  if (max < strlen (name) * 2)  /* *2 because "recoded" in UTF16-LE. */
    parent_nk->max_subkey_name_len = htole16 (strlen (name) * 2);

  return node;
}

/* Decrement the refcount of an sk-record, and if it reaches zero,
 * unlink it from the chain and delete it.
 */
static int
delete_sk (hive_h *h, size_t sk_offset)
{
  if (!IS_VALID_BLOCK (h, sk_offset) || !BLOCK_ID_EQ (h, sk_offset, "sk")) {
    if (h->msglvl >= 2)
      fprintf (stderr, "delete_sk: not an sk record: 0x%zx\n", sk_offset);
    errno = EFAULT;
    return -1;
  }

  struct ntreg_sk_record *sk = (struct ntreg_sk_record *) (h->addr + sk_offset);

  if (sk->refcount == 0) {
    if (h->msglvl >= 2)
      fprintf (stderr, "delete_sk: sk record already has refcount 0: 0x%zx\n",
               sk_offset);
    errno = EINVAL;
    return -1;
  }

  sk->refcount--;

  if (sk->refcount == 0) {
    size_t sk_prev_offset = sk->sk_prev;
    sk_prev_offset += 0x1000;

    size_t sk_next_offset = sk->sk_next;
    sk_next_offset += 0x1000;

    /* Update sk_prev/sk_next SKs, unless they both point back to this
     * cell in which case we are deleting the last SK.
     */
    if (sk_prev_offset != sk_offset && sk_next_offset != sk_offset) {
      struct ntreg_sk_record *sk_prev =
        (struct ntreg_sk_record *) (h->addr + sk_prev_offset);
      struct ntreg_sk_record *sk_next =
        (struct ntreg_sk_record *) (h->addr + sk_next_offset);

      sk_prev->sk_next = htole32 (sk_next_offset - 0x1000);
      sk_next->sk_prev = htole32 (sk_prev_offset - 0x1000);
    }

    /* Refcount is zero so really delete this block. */
    mark_block_unused (h, sk_offset);
  }

  return 0;
}

/* Callback from hivex_node_delete_child which is called to delete a
 * node AFTER its subnodes have been visited.  The subnodes have been
 * deleted but we still have to delete any lf/lh/li/ri records and the
 * value list block and values, followed by deleting the node itself.
 */
static int
delete_node (hive_h *h, void *opaque, hive_node_h node, const char *name)
{
  /* Get the intermediate blocks.  The subkeys have already been
   * deleted by this point, so tell get_children() not to check for
   * validity of the nk-records.
   */
  hive_node_h *unused;
  size_t *blocks;
  if (get_children (h, node, &unused, &blocks, GET_CHILDREN_NO_CHECK_NK) == -1)
    return -1;
  free (unused);

  /* We don't care what's in these intermediate blocks, so we can just
   * delete them unconditionally.
   */
  size_t i;
  for (i = 0; blocks[i] != 0; ++i)
    mark_block_unused (h, blocks[i]);

  free (blocks);

  /* Delete the values in the node. */
  if (delete_values (h, node) == -1)
    return -1;

  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + node);

  /* If the NK references an SK, delete it. */
  size_t sk_offs = le32toh (nk->sk);
  if (sk_offs != 0xffffffff) {
    sk_offs += 0x1000;
    if (delete_sk (h, sk_offs) == -1)
      return -1;
    nk->sk = htole32 (0xffffffff);
  }

  /* If the NK references a classname, delete it. */
  size_t cl_offs = le32toh (nk->classname);
  if (cl_offs != 0xffffffff) {
    cl_offs += 0x1000;
    mark_block_unused (h, cl_offs);
    nk->classname = htole32 (0xffffffff);
  }

  /* Delete the node itself. */
  mark_block_unused (h, node);

  return 0;
}

int
hivex_node_delete_child (hive_h *h, hive_node_h node)
{
  if (!h->writable) {
    errno = EROFS;
    return -1;
  }

  if (!IS_VALID_BLOCK (h, node) || !BLOCK_ID_EQ (h, node, "nk")) {
    errno = EINVAL;
    return -1;
  }

  if (node == hivex_root (h)) {
    if (h->msglvl >= 2)
      fprintf (stderr, "hivex_node_delete_child: cannot delete root node\n");
    errno = EINVAL;
    return -1;
  }

  hive_node_h parent = hivex_node_parent (h, node);
  if (parent == 0)
    return -1;

  /* Delete node and all its children and values recursively. */
  static const struct hivex_visitor visitor = { .node_end = delete_node };
  if (hivex_visit_node (h, node, &visitor, sizeof visitor, NULL, 0) == -1)
    return -1;

  /* Delete the link from parent to child.  We need to find the lf/lh
   * record which contains the offset and remove the offset from that
   * record, then decrement the element count in that record, and
   * decrement the overall number of subkeys stored in the parent
   * node.
   */
  hive_node_h *unused;
  size_t *blocks;
  if (get_children (h, parent, &unused, &blocks, GET_CHILDREN_NO_CHECK_NK)== -1)
    return -1;
  free (unused);

  size_t i, j;
  for (i = 0; blocks[i] != 0; ++i) {
    struct ntreg_hbin_block *block =
      (struct ntreg_hbin_block *) (h->addr + blocks[i]);

    if (block->id[0] == 'l' && (block->id[1] == 'f' || block->id[1] == 'h')) {
      struct ntreg_lf_record *lf = (struct ntreg_lf_record *) block;

      size_t nr_subkeys_in_lf = le16toh (lf->nr_keys);

      for (j = 0; j < nr_subkeys_in_lf; ++j)
        if (le32toh (lf->keys[j].offset) + 0x1000 == node) {
          for (; j < nr_subkeys_in_lf - 1; ++j)
            memcpy (&lf->keys[j], &lf->keys[j+1], sizeof (lf->keys[j]));
          lf->nr_keys = htole16 (nr_subkeys_in_lf - 1);
          goto found;
        }
    }
  }
  if (h->msglvl >= 2)
    fprintf (stderr, "hivex_node_delete_child: could not find parent to child link\n");
  errno = ENOTSUP;
  return -1;

 found:;
  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + parent);
  size_t nr_subkeys_in_nk = le32toh (nk->nr_subkeys);
  nk->nr_subkeys = htole32 (nr_subkeys_in_nk - 1);

  if (h->msglvl >= 2)
    fprintf (stderr, "hivex_node_delete_child: updating nr_subkeys in parent 0x%zx to %zu\n",
             parent, nr_subkeys_in_nk);

  return 0;
}

int
hivex_node_set_values (hive_h *h, hive_node_h node,
                       size_t nr_values, const hive_set_value *values,
                       int flags)
{
  if (!h->writable) {
    errno = EROFS;
    return -1;
  }

  if (!IS_VALID_BLOCK (h, node) || !BLOCK_ID_EQ (h, node, "nk")) {
    errno = EINVAL;
    return -1;
  }

  /* Delete all existing values. */
  if (delete_values (h, node) == -1)
    return -1;

  if (nr_values == 0)
    return 0;

  /* Allocate value list node.  Value lists have no id field. */
  static const char nul_id[2] = { 0, 0 };
  size_t seg_len =
    sizeof (struct ntreg_value_list) + (nr_values - 1) * sizeof (uint32_t);
  size_t vallist_offs = allocate_block (h, seg_len, nul_id);
  if (vallist_offs == 0)
    return -1;

  struct ntreg_nk_record *nk = (struct ntreg_nk_record *) (h->addr + node);
  nk->nr_values = htole32 (nr_values);
  nk->vallist = htole32 (vallist_offs - 0x1000);

  struct ntreg_value_list *vallist =
    (struct ntreg_value_list *) (h->addr + vallist_offs);

  size_t i;
  for (i = 0; i < nr_values; ++i) {
    /* Allocate vk record to store this (key, value) pair. */
    static const char vk_id[2] = { 'v', 'k' };
    seg_len = sizeof (struct ntreg_vk_record) + strlen (values[i].key);
    size_t vk_offs = allocate_block (h, seg_len, vk_id);
    if (vk_offs == 0)
      return -1;

    vallist->offset[i] = htole32 (vk_offs - 0x1000);

    struct ntreg_vk_record *vk = (struct ntreg_vk_record *) (h->addr + vk_offs);
    size_t name_len = strlen (values[i].key);
    vk->name_len = htole16 (name_len);
    strcpy (vk->name, values[i].key);
    vk->data_type = htole32 (values[i].t);
    uint32_t len = values[i].len;
    if (len <= 4)               /* store it inline => set MSB flag */
      len |= 0x80000000;
    vk->data_len = htole32 (len);
    vk->flags = name_len == 0 ? 0 : 1;

    if (values[i].len <= 4)     /* store it inline */
      memcpy (&vk->data_offset, values[i].value, values[i].len);
    else {
      size_t offs = allocate_block (h, values[i].len + 4, nul_id);
      if (offs == 0)
        return -1;
      memcpy (h->addr + offs + 4, values[i].value, values[i].len);
      vk->data_offset = htole32 (offs - 0x1000);
    }

    if (name_len * 2 > le32toh (nk->max_vk_name_len))
      /* * 2 for UTF16-LE "reencoding" */
      nk->max_vk_name_len = htole32 (name_len * 2);
    if (values[i].len > le32toh (nk->max_vk_data_len))
      nk->max_vk_data_len = htole32 (values[i].len);
  }

  return 0;
}
