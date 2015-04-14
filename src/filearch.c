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

#ifdef HAVE_LIBMAGIC
#include <magic.h>
#endif

#include "ignore-value.h"

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"
#include "guestfs_protocol.h"

#if defined(HAVE_LIBMAGIC)

static pcre *re_file_elf;
static pcre *re_elf_ppc64;

static void compile_regexps (void) __attribute__((constructor));
static void free_regexps (void) __attribute__((destructor));

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

static void
free_regexps (void)
{
  pcre_free (re_file_elf);
  pcre_free (re_elf_ppc64);
}

# ifdef HAVE_ATTRIBUTE_CLEANUP
# define CLEANUP_MAGIC_T_FREE __attribute__((cleanup(cleanup_magic_t_free)))

static void
cleanup_magic_t_free (void *ptr)
{
  magic_t m = *(magic_t *) ptr;

  if (m)
    magic_close (m);
}

# else
# define CLEANUP_MAGIC_T_FREE
# endif

/* Convert output from 'file' command on ELF files to the canonical
 * architecture string.  Caller must free the result.
 */
static char *
canonical_elf_arch (guestfs_h *g, const char *elf_arch)
{
  const char *r;
  char *ret;

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
  else if (strstr (elf_arch, "ARM aarch64"))
    r = "aarch64";
  else if (strstr (elf_arch, "ARM"))
    r = "arm";
  else
    r = elf_arch;

  ret = safe_strdup (g, r);
  return ret;
}

static int
is_regular_file (const char *filename)
{
  struct stat statbuf;

  return lstat (filename, &statbuf) == 0 && S_ISREG (statbuf.st_mode);
}

static char *
magic_for_file (guestfs_h *g, const char *filename, bool *loading_ok,
                bool *matched)
{
  int flags;
  CLEANUP_MAGIC_T_FREE magic_t m = NULL;
  const char *line;
  char *elf_arch;

  flags = g->verbose ? MAGIC_DEBUG : 0;
  flags |= MAGIC_ERROR | MAGIC_RAW;

  if (loading_ok)
    *loading_ok = false;
  if (matched)
    *matched = false;

  m = magic_open (flags);
  if (m == NULL) {
    perrorf (g, "magic_open");
    return NULL;
  }

  if (magic_load (m, NULL) == -1) {
    perrorf (g, "magic_load: default magic database file");
    return NULL;
  }

  line = magic_file (m, filename);
  if (line == NULL) {
    perrorf (g, "magic_file: %s", filename);
    return NULL;
  }

  if (loading_ok)
    *loading_ok = true;

  elf_arch = match1 (g, line, re_file_elf);
  if (elf_arch == NULL) {
    error (g, "no re_file_elf match in '%s'", line);
    return NULL;
  }

  if (matched)
    *matched = true;

  return canonical_elf_arch (g, elf_arch);
}

/* Download and uncompress the cpio file to find binaries within. */
static const char *initrd_binaries[] = {
  "bin/ls",
  "bin/rm",
  "bin/modprobe",
  "sbin/modprobe",
  "bin/sh",
  "bin/bash",
  "bin/dash",
  "bin/nash",
  NULL
};

static char *
cpio_arch (guestfs_h *g, const char *file, const char *path)
{
  CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g), *dir = NULL;
  CLEANUP_FREE char *initrd = NULL;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs___new_command (g);
  char *ret = NULL;
  const char *method;
  int64_t size;
  int r;
  size_t i;

  if (asprintf (&dir, "%s/libguestfsXXXXXX", tmpdir) == -1) {
    perrorf (g, "asprintf");
    return NULL;
  }

  if (strstr (file, "gzip"))
    method = "zcat";
  else if (strstr (file, "bzip2"))
    method = "bzcat";
  else
    method = "cat";

  /* Security: Refuse to download initrd if it is huge. */
  size = guestfs_filesize (g, path);
  if (size == -1 || size > 100000000) {
    error (g, _("size of %s unreasonable (%" PRIi64 " bytes)"),
           path, size);
    goto out;
  }

  if (mkdtemp (dir) == NULL) {
    perrorf (g, "mkdtemp");
    goto out;
  }

  initrd = safe_asprintf (g, "%s/initrd", dir);
  if (guestfs_download (g, path, initrd) == -1)
    goto out;

  /* Construct a command to extract named binaries from the initrd file. */
  guestfs___cmd_add_string_unquoted (cmd, "cd ");
  guestfs___cmd_add_string_quoted   (cmd, dir);
  guestfs___cmd_add_string_unquoted (cmd, " && ");
  guestfs___cmd_add_string_unquoted (cmd, method);
  guestfs___cmd_add_string_unquoted (cmd, " initrd | cpio --quiet -id");
  for (i = 0; initrd_binaries[i] != NULL; ++i) {
    guestfs___cmd_add_string_unquoted (cmd, " ");
    guestfs___cmd_add_string_quoted (cmd, initrd_binaries[i]);
  }

  r = guestfs___cmd_run (cmd);
  if (r == -1)
    goto out;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs___external_command_failed (g, r, "cpio", path);
    goto out;
  }

  for (i = 0; initrd_binaries[i] != NULL; ++i) {
    CLEANUP_FREE char *bin =
      safe_asprintf (g, "%s/%s", dir, initrd_binaries[i]);

    if (is_regular_file (bin)) {
      bool loading_ok, matched;

      ret = magic_for_file (g, bin, &loading_ok, &matched);
      if (!loading_ok || matched)
        goto out;
    }
  }
  error (g, "file_architecture: could not determine architecture of cpio archive");

 out:
  guestfs___recursive_remove_dir (g, dir);

  return ret;
}

static char *
compressed_file_arch (guestfs_h *g, const char *path, const char *method)
{
  CLEANUP_FREE char *tmpdir = guestfs_get_tmpdir (g), *dir = NULL;
  CLEANUP_FREE char *tempfile = NULL, *tempfile_extracted = NULL;
  CLEANUP_CMD_CLOSE struct command *cmd = guestfs_int_new_command (g);
  char *ret = NULL;
  int64_t size;
  int r;
  bool matched;

  if (asprintf (&dir, "%s/libguestfsXXXXXX", tmpdir) == -1) {
    perrorf (g, "asprintf");
    return NULL;
  }

  /* Security: Refuse to download file if it is huge. */
  size = guestfs_filesize (g, path);
  if (size == -1 || size > 10000000) {
    error (g, _("size of %s unreasonable (%" PRIi64 " bytes)"),
           path, size);
    goto out;
  }

  if (mkdtemp (dir) == NULL) {
    perrorf (g, "mkdtemp");
    goto out;
  }

  tempfile = safe_asprintf (g, "%s/file", dir);
  if (guestfs_download (g, path, tempfile) == -1)
    goto out;

  tempfile_extracted = safe_asprintf (g, "%s/file_extracted", dir);

  /* Construct a command to extract named binaries from the initrd file. */
  guestfs_int_cmd_add_string_unquoted (cmd, method);
  guestfs_int_cmd_add_string_unquoted (cmd, " ");
  guestfs_int_cmd_add_string_quoted (cmd, tempfile);
  guestfs_int_cmd_add_string_unquoted (cmd, " > ");
  guestfs_int_cmd_add_string_quoted (cmd, tempfile_extracted);

  r = guestfs_int_cmd_run (cmd);
  if (r == -1)
    goto out;
  if (!WIFEXITED (r) || WEXITSTATUS (r) != 0) {
    guestfs_int_external_command_failed (g, r, method, path);
    goto out;
  }

  ret = magic_for_file (g, tempfile_extracted, NULL, &matched);
  if (!matched)
    error (g, "file_architecture: could not determine architecture of compressed file");

 out:
  guestfs_int_recursive_remove_dir (g, dir);

  return ret;
}

char *
guestfs__file_architecture (guestfs_h *g, const char *path)
{
  CLEANUP_FREE char *file = NULL;
  CLEANUP_FREE char *elf_arch = NULL;
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
  else if (strstr (file, "gzip compressed data"))
    ret = compressed_file_arch (g, path, "zcat");
  else if (strstr (file, "XZ compressed data"))
    ret = compressed_file_arch (g, path, "xzcat");
  else
    error (g, "file_architecture: unknown architecture: %s", path);

  return ret;                   /* caller frees */
}

#else /* no libmagic at compile time */

/* XXX Should be an optgroup. */

#define NOT_IMPL(r)                                                     \
  error (g, _("file-architecture API not available since this version of libguestfs was compiled without the libmagic library")); \
  return r

char *
guestfs__file_architecture (guestfs_h *g, const char *path)
{
  NOT_IMPL(NULL);
}

#endif /* no libmagic at compile time */
