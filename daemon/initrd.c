/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include "guestfs_protocol.h"
#include "daemon.h"
#include "actions.h"

/* Length of a newc/crc format cpio entry header (not including the
 * filename which follows it).
 */
#define CPIO_NEWC_HDR_LEN 110

enum initrd_compression {
  COMPRESS_NONE,
  COMPRESS_GZIP,
  COMPRESS_BZIP2,
  COMPRESS_XZ,
  COMPRESS_ZSTD,
};

static const char *
decompressor_command (enum initrd_compression compression)
{
  switch (compression) {
  case COMPRESS_GZIP:   return "zcat";
  case COMPRESS_BZIP2:  return "bzcat";
  case COMPRESS_XZ:     return "xzcat";
  case COMPRESS_ZSTD:   return "zstdcat";
  case COMPRESS_NONE:
  default:              return "cat";
  }
}

static int
is_cpio_magic (const unsigned char *magic)
{
  return memcmp (magic, "070701", 6) == 0 || memcmp (magic, "070702", 6) == 0;
}

/**
 * Modern initramfs images are often composed of several concatenated
 * cpio archives: one or more uncompressed "early cpio" archives
 * (used by the kernel/dracut to carry CPU microcode etc, see
 * F<Documentation/x86/microcode.rst> in the kernel sources) followed
 * by the main, compressed cpio archive containing the real
 * initramfs contents.
 *
 * This parses a single newc/crc format cpio archive starting at
 * C<offset> in C<fd>, up to and including its C<TRAILER!!!> entry,
 * and returns the offset of the byte following it, rounded up to
 * the next 512-byte boundary (early cpio archives are padded to a
 * block boundary before the next archive is appended).  Returns
 * C<-1> if the archive is truncated or malformed.
 */
static off_t
skip_early_cpio_archive (int fd, off_t offset, off_t file_size)
{
  unsigned char hdr[CPIO_NEWC_HDR_LEN];
  char field[9];
  long namesize, filesize;
  off_t name_offset, data_offset, next;
  CLEANUP_FREE char *name = NULL;

  field[8] = '\0';

  for (;;) {
    if (offset + CPIO_NEWC_HDR_LEN > file_size)
      return -1;
    if (pread (fd, hdr, CPIO_NEWC_HDR_LEN, offset) != CPIO_NEWC_HDR_LEN)
      return -1;
    if (!is_cpio_magic (hdr))
      return -1;

    /* c_filesize is the 7th 8-hex-digit field, c_namesize is the
     * 12th, each starting right after the 6-byte magic.
     */
    memcpy (field, hdr + 6 + 6*8, 8);
    filesize = strtol (field, NULL, 16);
    memcpy (field, hdr + 6 + 11*8, 8);
    namesize = strtol (field, NULL, 16);

    if (namesize <= 0 || namesize > PATH_MAX || filesize < 0)
      return -1;

    name_offset = offset + CPIO_NEWC_HDR_LEN;
    if (name_offset + namesize > file_size)
      return -1;

    free (name);
    name = malloc (namesize + 1);
    if (name == NULL)
      return -1;
    if (pread (fd, name, namesize, name_offset) != namesize)
      return -1;
    name[namesize] = '\0';

    /* Header + filename is padded to a 4-byte boundary, then the
     * file data follows and is itself padded to a 4-byte boundary.
     */
    data_offset = (name_offset + namesize + 3) & ~(off_t)3;
    next = (data_offset + filesize + 3) & ~(off_t)3;

    if (STREQ (name, "TRAILER!!!"))
      return (next + 511) & ~(off_t)511;

    offset = next;
  }
}

/**
 * Work out where the "real" (possibly compressed) cpio archive
 * starts within C<path>, skipping over any leading uncompressed
 * early cpio archives, and detect its compression format (if any)
 * by looking at its magic bytes.
 *
 * Returns 0 on success, or -1 on error (having already called
 * C<reply_with_*>).
 */
static int
detect_initrd (const char *path, off_t *offset_r,
               enum initrd_compression *compression_r)
{
  CLEANUP_FREE char *fullpath = NULL;
  int fd;
  struct stat statbuf;
  off_t offset = 0, next;
  unsigned char magic[6];

  fullpath = sysroot_path (path);
  if (fullpath == NULL) {
    reply_with_perror ("malloc");
    return -1;
  }

  fd = open (fullpath, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("open: %s", path);
    return -1;
  }
  if (fstat (fd, &statbuf) == -1) {
    reply_with_perror ("fstat: %s", path);
    close (fd);
    return -1;
  }

  while (offset + (off_t) sizeof magic <= statbuf.st_size &&
         pread (fd, magic, sizeof magic, offset) == (ssize_t) sizeof magic &&
         is_cpio_magic (magic)) {
    next = skip_early_cpio_archive (fd, offset, statbuf.st_size);
    if (next < 0 || next >= statbuf.st_size)
      break;
    offset = next;
  }

  if (pread (fd, magic, sizeof magic, offset) < 4)
    *compression_r = COMPRESS_NONE;
  else if (magic[0] == 0x1f && magic[1] == 0x8b)
    *compression_r = COMPRESS_GZIP;
  else if (magic[0] == 0x42 && magic[1] == 0x5a && magic[2] == 0x68)
    *compression_r = COMPRESS_BZIP2;
  else if (magic[0] == 0xfd && magic[1] == 0x37 && magic[2] == 0x7a &&
           magic[3] == 0x58)
    *compression_r = COMPRESS_XZ;
  else if (magic[0] == 0x28 && magic[1] == 0xb5 && magic[2] == 0x2f &&
           magic[3] == 0xfd)
    *compression_r = COMPRESS_ZSTD;
  else
    *compression_r = COMPRESS_NONE;

  close (fd);
  *offset_r = offset;
  return 0;
}

/* Write the pipeline needed to produce the decompressed cpio stream
 * for <path> to fp, ie. "[tail -c +N <path> |] <decompressor> <path>".
 */
static void
write_decompress_pipeline (FILE *fp, const char *path,
                           off_t offset, enum initrd_compression compression)
{
  const char *decompressor = decompressor_command (compression);

  if (offset > 0) {
    fprintf (fp, "tail -c +%lld ", (long long) offset + 1);
    sysroot_shell_quote (path, fp);
    fprintf (fp, " | %s", decompressor);
  }
  else {
    fprintf (fp, "%s ", decompressor);
    sysroot_shell_quote (path, fp);
  }
}

char **
do_initrd_list (const char *path)
{
  FILE *fp;
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
  CLEANUP_FREE_STRINGSBUF DECLARE_STRINGSBUF (filenames);
  CLEANUP_FREE char *filename = NULL;
  size_t allocsize;
  ssize_t len;
  int ret;
  off_t offset;
  enum initrd_compression compression;

  if (detect_initrd (path, &offset, &compression) == -1)
    return NULL;

  /* "[tail -c +N /sysroot/<path> |] zcat | cpio --quiet -it" */
  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    reply_with_perror ("open_memstream");
    return NULL;
  }
  write_decompress_pipeline (fp, path, offset, compression);
  fprintf (fp, " | cpio --quiet -it");
  if (fclose (fp) == EOF)
    goto cmd_error;

  if (verbose)
    fprintf (stderr, "%s\n", cmd);

  fp = popen (cmd, "r");
  if (fp == NULL) {
    reply_with_perror ("popen: %s", cmd);
    return NULL;
  }

  allocsize = 0;
  while ((len = getline (&filename, &allocsize, fp)) != -1) {
    if (len > 0 && filename[len-1] == '\n')
      filename[len-1] = '\0';
    if (add_string (&filenames, filename) == -1) {
      pclose (fp);
      return NULL;
    }
  }

  if (end_stringsbuf (&filenames) == -1) {
    pclose (fp);
    return NULL;
  }

  ret = pclose (fp);
  if (ret != 0) {
    if (ret == -1)
      reply_with_perror ("pclose");
    else {
      if (WEXITSTATUS (ret) != 0)
        ret = WEXITSTATUS (ret);
      reply_with_error ("pclose: command failed with return code %d", ret);
    }
    return NULL;
  }

  return take_stringsbuf (&filenames);
}

char *
do_initrd_cat (const char *path, const char *filename, size_t *size_r)
{
  char tmpdir[] = "/tmp/initrd-cat-XXXXXX";
  CLEANUP_FREE char *cmd = NULL;
  size_t cmd_size;
  FILE *fp;
  struct stat statbuf;
  int fd, r;
  char *ret = NULL;
  CLEANUP_FREE char *fullpath = NULL;
  off_t offset;
  enum initrd_compression compression;

  if (detect_initrd (path, &offset, &compression) == -1)
    return NULL;

  if (mkdtemp (tmpdir) == NULL) {
    reply_with_perror ("mkdtemp");
    return NULL;
  }

  /* Extract file into temporary directory.  This may create subdirs.
   * It's also possible that this doesn't create anything at all
   * (eg. if the named file does not exist in the cpio archive) --
   * cpio is silent in this case.
   */
  /* "cd tmpdir && [tail -c +N |] zcat /sysroot/<path> | cpio --quiet -id file",
   * but paths must be quoted.
   */
  fp = open_memstream (&cmd, &cmd_size);
  if (fp == NULL) {
  cmd_error:
    reply_with_perror ("open_memstream");
    rmdir (tmpdir);
    return NULL;
  }
  fprintf (fp, "cd ");
  shell_quote (tmpdir, fp);
  fprintf (fp, " && ");
  write_decompress_pipeline (fp, path, offset, compression);
  fprintf (fp, " | cpio --quiet -id ");
  shell_quote (filename, fp);
  if (fclose (fp) == EOF)
    goto cmd_error;

  r = system (cmd);
  if (r == -1) {
    reply_with_perror ("command failed: %s", cmd);
    rmdir (tmpdir);
    return NULL;
  }
  if (WEXITSTATUS (r) != 0) {
    reply_with_perror ("command failed with return code %d",
                       WEXITSTATUS (r));
    rmdir (tmpdir);
    return NULL;
  }

  /* Construct the expected name of the extracted file. */
  if (asprintf (&fullpath, "%s/%s", tmpdir, filename) == -1) {
    reply_with_perror ("asprintf");
    rmdir (tmpdir);
    return NULL;
  }

  /* See if we got a file. */
  fd = open (fullpath, O_RDONLY|O_CLOEXEC);
  if (fd == -1) {
    reply_with_perror ("open: %s:%s", path, filename);
    rmdir (tmpdir);
    return NULL;
  }

  /* From this point, we know the file exists, so we require full
   * cleanup.
   */
  if (fstat (fd, &statbuf) == -1) {
    reply_with_perror ("fstat: %s:%s", path, filename);
    goto cleanup;
  }

  /* The actual limit on messages is smaller than this.  This
   * check just limits the amount of memory we'll try and allocate
   * here.  If the message is larger than the real limit, that will
   * be caught later when we try to serialize the message.
   */
  if (statbuf.st_size >= GUESTFS_MESSAGE_MAX) {
    reply_with_error ("%s:%s: file is too large for the protocol",
                      path, filename);
    goto cleanup;
  }

  ret = malloc (statbuf.st_size);
  if (ret == NULL) {
    reply_with_perror ("malloc");
    goto cleanup;
  }

  if (xread (fd, ret, statbuf.st_size) == -1) {
    reply_with_perror ("read: %s:%s", path, filename);
    free (ret);
    ret = NULL;
    goto cleanup;
  }

  if (close (fd) == -1) {
    reply_with_perror ("close: %s:%s", path, filename);
    free (ret);
    ret = NULL;
    goto cleanup;
  }
  fd = -1;

  /* Mustn't touch *size_r until we are sure that we won't return any
   * error (RHBZ#589039).
   */
  *size_r = statbuf.st_size;

 cleanup:
  if (fd >= 0)
    close (fd);

  /* Remove the file. */
  if (unlink (fullpath) == -1) {
    fprintf (stderr, "unlink: %s: %m\n", fullpath);
    /* non-fatal */
  }

  /* Remove the directories up to and including the temp directory. */
  do {
    char *p = strrchr (fullpath, '/');
    if (!p) break;
    *p = '\0';
    if (rmdir (fullpath) == -1) {
      fprintf (stderr, "rmdir: %s: %m\n", fullpath);
      /* non-fatal */
    }
  } while (STRNEQ (fullpath, tmpdir));

  return ret;
}
