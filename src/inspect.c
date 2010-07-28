/* libguestfs
 * Copyright (C) 2010 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>

#include <pcre.h>
#include <magic.h>

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

/* Compile all the regular expressions once when the shared library is
 * loaded.  PCRE is thread safe so we're supposedly OK here if
 * multiple threads call into the libguestfs API functions below
 * simultaneously.
 */
static pcre *re_file_elf;
static pcre *re_file_win64;
static pcre *re_elf_ppc64;

static void compile_regexps (void) __attribute__((constructor));
static void
compile_regexps (void)
{
  const char *err;
  int offset;

#define COMPILE(re,pattern,options)                                     \
  do {                                                                  \
    re = pcre_compile ((pattern), (options), &err, &offset, NULL);      \
    if (re == NULL) {                                                   \
      ignore_value (write (2, err, strlen (err)));                      \
      abort ();                                                         \
    }                                                                   \
  } while (0)

  COMPILE (re_file_elf,
           "ELF.*(?:executable|shared object|relocatable), (.+?),", 0);
  COMPILE (re_elf_ppc64, "64.*PowerPC", 0);
}

/* Match a regular expression which contains no captures.  Returns
 * true if it matches or false if it doesn't.
 */
static int
match (guestfs_h *g, const char *str, const pcre *re)
{
  size_t len = strlen (str);
  int vec[30], r;

  r = pcre_exec (re, NULL, str, len, 0, 0, vec, sizeof vec / sizeof vec[0]);
  if (r == PCRE_ERROR_NOMATCH)
    return 0;
  if (r != 1) {
    /* Internal error -- should not happen. */
    fprintf (stderr, "libguestfs: %s: %s: internal error: pcre_exec returned unexpected error code %d when matching against the string \"%s\"\n",
             __FILE__, __func__, r, str);
    return 0;
  }

  return 1;
}

/* Match a regular expression which contains exactly one capture.  If
 * the string matches, return the capture, otherwise return NULL.  The
 * caller must free the result.
 */
static char *
match1 (guestfs_h *g, const char *str, const pcre *re)
{
  size_t len = strlen (str);
  int vec[30], r;

  r = pcre_exec (re, NULL, str, len, 0, 0, vec, sizeof vec / sizeof vec[0]);
  if (r == PCRE_ERROR_NOMATCH)
    return NULL;
  if (r != 2) {
    /* Internal error -- should not happen. */
    fprintf (stderr, "libguestfs: %s: %s: internal error: pcre_exec returned unexpected error code %d when matching against the string \"%s\"\n",
             __FILE__, __func__, r, str);
    return NULL;
  }

  return safe_strndup (g, &str[vec[2]], vec[3]-vec[2]);
}

/* Convert output from 'file' command on ELF files to the canonical
 * architecture string.  Caller must free the result.
 */
static char *
canonical_elf_arch (guestfs_h *g, const char *elf_arch)
{
  const char *r;

  if (strstr (elf_arch, "Intel 80386"))
    r = "i386";
  else if (strstr (elf_arch, "Intel 80486"))
    r = "i486";
  else if (strstr (elf_arch, "x86-64"))
    r = "x86_64";
  else if (strstr (elf_arch, "AMD x86-64"))
    r = "x86_64";
  else if (strstr (elf_arch, "SPARC32"))
    r = "sparc";
  else if (strstr (elf_arch, "SPARC V9"))
    r = "sparc64";
  else if (strstr (elf_arch, "IA-64"))
    r = "ia64";
  else if (match (g, elf_arch, re_elf_ppc64))
    r = "ppc64";
  else if (strstr (elf_arch, "PowerPC"))
    r = "ppc";
  else
    r = elf_arch;

  char *ret = safe_strdup (g, r);
  return ret;
}

static int
is_regular_file (const char *filename)
{
  struct stat statbuf;

  return lstat (filename, &statbuf) == 0 && S_ISREG (statbuf.st_mode);
}

/* Download and uncompress the cpio file to find binaries within.
 * Notes:
 * (1) Two lists must be identical.
 * (2) Implicit limit of 31 bytes for length of each element (see code
 * below).
 */
#define INITRD_BINARIES1 "bin/ls bin/rm bin/modprobe sbin/modprobe bin/sh bin/bash bin/dash bin/nash"
#define INITRD_BINARIES2 {"bin/ls", "bin/rm", "bin/modprobe", "sbin/modprobe", "bin/sh", "bin/bash", "bin/dash", "bin/nash"}

static char *
cpio_arch (guestfs_h *g, const char *file, const char *path)
{
  char *ret = NULL;

  const char *method;
  if (strstr (file, "gzip"))
    method = "zcat";
  else if (strstr (file, "bzip2"))
    method = "bzcat";
  else
    method = "cat";

  char dir[] = "/tmp/initrd.XXXXXX";
#define dir_len (sizeof dir)
  if (mkdtemp (dir) == NULL) {
    perrorf (g, "mkdtemp");
    goto out;
  }

  char dir_initrd[dir_len + 16];
  snprintf (dir_initrd, dir_len + 16, "%s/initrd", dir);
  if (guestfs_download (g, path, dir_initrd) == -1)
    goto out;

  char cmd[dir_len + 256];
  snprintf (cmd, dir_len + 256,
            "cd %s && %s initrd | cpio --quiet -id " INITRD_BINARIES1,
            dir, method);
  int r = system (cmd);
  if (r == -1 || WEXITSTATUS (r) != 0) {
    perrorf (g, "cpio command failed");
    goto out;
  }

  char bin[dir_len + 32];
  const char *bins[] = INITRD_BINARIES2;
  size_t i;
  for (i = 0; i < sizeof bins / sizeof bins[0]; ++i) {
    snprintf (bin, dir_len + 32, "%s/%s", dir, bins[i]);

    if (is_regular_file (bin)) {
      int flags = g->verbose ? MAGIC_DEBUG : 0;
      flags |= MAGIC_ERROR | MAGIC_RAW;

      magic_t m = magic_open (flags);
      if (m == NULL) {
        perrorf (g, "magic_open");
        goto out;
      }

      if (magic_load (m, NULL) == -1) {
        perrorf (g, "magic_load: default magic database file");
        magic_close (m);
        goto out;
      }

      const char *line = magic_file (m, bin);
      if (line == NULL) {
        perrorf (g, "magic_file: %s", bin);
        magic_close (m);
        goto out;
      }

      char *elf_arch;
      if ((elf_arch = match1 (g, line, re_file_elf)) != NULL) {
        ret = canonical_elf_arch (g, elf_arch);
        free (elf_arch);
        magic_close (m);
        goto out;
      }
      magic_close (m);
    }
  }
  error (g, "file_architecture: could not determine architecture of cpio archive");

 out:
  /* Free up the temporary directory.  Note the directory name cannot
   * contain shell meta-characters because of the way it was
   * constructed above.
   */
  snprintf (cmd, dir_len + 256, "rm -rf %s", dir);
  ignore_value (system (cmd));

  return ret;
#undef dir_len
}

char *
guestfs__file_architecture (guestfs_h *g, const char *path)
{
  char *file = NULL;
  char *elf_arch = NULL;
  char *ret = NULL;

  /* Get the output of the "file" command.  Note that because this
   * runs in the daemon, LANG=C so it's in English.
   */
  file = guestfs_file (g, path);
  if (file == NULL)
    return NULL;

  if ((elf_arch = match1 (g, file, re_file_elf)) != NULL)
    ret = canonical_elf_arch (g, elf_arch);
  else if (strstr (file, "PE32 executable"))
    ret = safe_strdup (g, "i386");
  else if (strstr (file, "PE32+ executable"))
    ret = safe_strdup (g, "x86_64");
  else if (strstr (file, "cpio archive"))
    ret = cpio_arch (g, file, path);
  else
    error (g, "file_architecture: unknown architecture: %s", path);

  free (file);
  free (elf_arch);
  return ret;                   /* caller frees */
}
