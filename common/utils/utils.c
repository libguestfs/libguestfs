/* libguestfs
 * Copyright (C) 2009-2017 Red Hat Inc.
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

/**
 * Utility functions used by the library, tools and language bindings.
 *
 * These functions these I<must not> call internal library functions
 * such as C<safe_*>, C<error> or C<perrorf>, or any C<guestfs_int_*>.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <libintl.h>

/* NB: MUST NOT require linking to gnulib, because that will break the
 * Python 'sdist' which includes a copy of this file.  It's OK to
 * include "c-ctype.h" and "ignore-value.h" here (since it is a header
 * only with no other code), but we also had to copy these files to
 * the Python sdist.
 */
#include "c-ctype.h"
#include "ignore-value.h"

/* NB: MUST NOT include "guestfs-internal.h". */
#include "guestfs.h"
#include "guestfs-utils.h"

void
guestfs_int_free_string_list (char **argv)
{
  size_t i;

  if (argv == NULL)
    return;

  for (i = 0; argv[i] != NULL; ++i)
    free (argv[i]);
  free (argv);
}

size_t
guestfs_int_count_strings (char *const *argv)
{
  size_t r;

  for (r = 0; argv[r]; ++r)
    ;

  return r;
}

char **
guestfs_int_copy_string_list (char *const *argv)
{
  const size_t n = guestfs_int_count_strings (argv);
  size_t i, j;
  char **ret;

  ret = malloc ((n+1) * sizeof (char *));
  if (ret == NULL)
    return NULL;
  ret[n] = NULL;

  for (i = 0; i < n; ++i) {
    ret[i] = strdup (argv[i]);
    if (ret[i] == NULL) {
      for (j = 0; j < i; ++j)
        free (ret[j]);
      free (ret);
      return NULL;
    }
  }

  return ret;
}

/* Note that near-identical functions exist in the daemon. */
char *
guestfs_int_concat_strings (char *const *argv)
{
  return guestfs_int_join_strings ("", argv);
}

char *
guestfs_int_join_strings (const char *sep, char *const *argv)
{
  size_t i, len, seplen, rlen;
  char *r;

  seplen = strlen (sep);

  len = 0;
  for (i = 0; argv[i] != NULL; ++i) {
    if (i > 0)
      len += seplen;
    len += strlen (argv[i]);
  }
  len++; /* for final \0 */

  r = malloc (len);
  if (r == NULL)
    return NULL;

  rlen = 0;
  for (i = 0; argv[i] != NULL; ++i) {
    if (i > 0) {
      memcpy (&r[rlen], sep, seplen);
      rlen += seplen;
    }
    len = strlen (argv[i]);
    memcpy (&r[rlen], argv[i], len);
    rlen += len;
  }
  r[rlen] = '\0';

  return r;
}

/**
 * Split string at separator character C<sep>, returning the list of
 * strings.  Returns C<NULL> on memory allocation failure.
 *
 * Note (assuming C<sep> is C<:>):
 *
 * =over 4
 *
 * =item C<str == NULL>
 *
 * aborts
 *
 * =item C<str == "">
 *
 * returns C<[]>
 *
 * =item C<str == "abc">
 *
 * returns C<["abc"]>
 *
 * =item C<str == ":">
 *
 * returns C<["", ""]>
 *
 * =back
 */
char **
guestfs_int_split_string (char sep, const char *str)
{
  size_t i, n, c;
  const size_t len = strlen (str);
  char reject[2] = { sep, '\0' };
  char **ret;

  /* We have to handle the empty string case differently else the code
   * below will return [""].
   */
  if (str[0] == '\0') {
    ret = malloc (1 * sizeof (char *));
    if (!ret)
      return NULL;
    ret[0] = NULL;
    return ret;
  }

  for (n = i = 0; i < len; ++i)
    if (str[i] == sep)
      n++;

  /* We always return a list of length 1 + (# separator characters).
   * We also have to add a trailing NULL.
   */
  ret = malloc ((n+2) * sizeof (char *));
  if (!ret)
    return NULL;
  ret[n+1] = NULL;

  for (n = i = 0; i <= len; ++i, ++n) {
    c = strcspn (&str[i], reject);
    ret[n] = strndup (&str[i], c);
    if (ret[n] == NULL) {
      for (i = 0; i < n; ++i)
        free (ret[i]);
      free (ret);
      return NULL;
    }
    i += c;
    if (str[i] == '\0') /* end of string? */
      break;
  }

  return ret;
}

/**
 * Translate a wait/system exit status into a printable string.
 */
char *
guestfs_int_exit_status_to_string (int status, const char *cmd_name,
				   char *buffer, size_t buflen)
{
  if (WIFEXITED (status)) {
    if (WEXITSTATUS (status) == 0)
      snprintf (buffer, buflen, _("%s exited successfully"),
                cmd_name);
    else
      snprintf (buffer, buflen, _("%s exited with error status %d"),
                cmd_name, WEXITSTATUS (status));
  }
  else if (WIFSIGNALED (status)) {
    snprintf (buffer, buflen, _("%s killed by signal %d (%s)"),
              cmd_name, WTERMSIG (status), strsignal (WTERMSIG (status)));
  }
  else if (WIFSTOPPED (status)) {
    snprintf (buffer, buflen, _("%s stopped by signal %d (%s)"),
              cmd_name, WSTOPSIG (status), strsignal (WSTOPSIG (status)));
  }
  else {
    snprintf (buffer, buflen, _("%s exited for an unknown reason (status %d)"),
              cmd_name, status);
  }

  return buffer;
}

/**
 * Return a random string of characters.
 *
 * Notes:
 *
 * =over 4
 *
 * =item *
 *
 * The C<ret> buffer must have length C<len+1> in order to store the
 * final C<\0> character.
 *
 * =item *
 *
 * There is about 5 bits of randomness per output character (so about
 * C<5*len> bits of randomness in the resulting string).
 *
 * =back
 */
int
guestfs_int_random_string (char *ret, size_t len)
{
  int fd;
  size_t i;
  unsigned char c;
  int saved_errno;

  fd = open ("/dev/urandom", O_RDONLY|O_CLOEXEC);
  if (fd == -1)
    return -1;

  for (i = 0; i < len; ++i) {
    if (read (fd, &c, 1) != 1) {
      saved_errno = errno;
      close (fd);
      errno = saved_errno;
      return -1;
    }
    /* Do not change this! */
    ret[i] = "0123456789abcdefghijklmnopqrstuvwxyz"[c % 36];
  }
  ret[len] = '\0';

  if (close (fd) == -1)
    return -1;

  return 0;
}

/**
 * This turns a drive index (eg. C<27>) into a drive name
 * (eg. C<"ab">).
 *
 * Drive indexes count from C<0>.  The return buffer has to be large
 * enough for the resulting string, and the returned pointer points to
 * the *end* of the string.
 *
 * L<https://rwmj.wordpress.com/2011/01/09/how-are-linux-drives-named-beyond-drive-26-devsdz/>
 */
char *
guestfs_int_drive_name (size_t index, char *ret)
{
  if (index >= 26)
    ret = guestfs_int_drive_name (index/26 - 1, ret);
  index %= 26;
  *ret++ = 'a' + index;
  *ret = '\0';
  return ret;
}

/**
 * The opposite of C<guestfs_int_drive_name>.  Take a string like
 * C<"ab"> and return the index (eg C<27>).
 *
 * Note that you must remove any prefix such as C<"hd">, C<"sd"> etc,
 * or any partition number before calling the function.
 */
ssize_t
guestfs_int_drive_index (const char *name)
{
  ssize_t r = 0;

  while (*name) {
    if (*name >= 'a' && *name <= 'z')
      r = 26*r + (*name - 'a' + 1);
    else
      return -1;
    name++;
  }

  return r-1;
}

/**
 * Similar to C<Tcl_GetBoolean>.
 */
int
guestfs_int_is_true (const char *str)
{
  if (STREQ (str, "1") ||
      STRCASEEQ (str, "true") ||
      STRCASEEQ (str, "t") ||
      STRCASEEQ (str, "yes") ||
      STRCASEEQ (str, "y") ||
      STRCASEEQ (str, "on"))
    return 1;

  if (STREQ (str, "0") ||
      STRCASEEQ (str, "false") ||
      STRCASEEQ (str, "f") ||
      STRCASEEQ (str, "no") ||
      STRCASEEQ (str, "n") ||
      STRCASEEQ (str, "off"))
    return 0;

  return -1;
}

/**
 * Check a string for validity, that it contains only certain
 * characters, and minimum and maximum length.  This function is
 * usually wrapped in a VALID_* macro, see F<lib/drives.c> for an
 * example.
 *
 * C<str> is the string to check.
 *
 * C<min_length> and C<max_length> are the minimum and maximum
 * length checks.  C<0> means no check.
 *
 * The flags control:
 *
 * =over 4
 *
 * =item C<VALID_FLAG_ALPHA>
 *
 * 7-bit ASCII-only alphabetic characters are permitted.
 *
 * =item C<VALID_FLAG_DIGIT>
 *
 * 7-bit ASCII-only digits are permitted.
 *
 * =back
 *
 * C<extra> is a set of extra characters permitted, in addition
 * to alphabetic and/or digits.  (C<extra = NULL> for no extra).
 *
 * Returns boolean C<true> if the string is valid (passes all the
 * tests), or C<false> if not.
 */
bool
guestfs_int_string_is_valid (const char *str,
                             size_t min_length, size_t max_length,
                             int flags, const char *extra)
{
  size_t i, len = strlen (str);

  if ((min_length > 0 && len < min_length) ||
      (max_length > 0 && len > max_length))
    return false;

  for (i = 0; i < len; ++i) {
    bool valid_char;

    valid_char =
      ((flags & VALID_FLAG_ALPHA) && c_isalpha (str[i])) ||
      ((flags & VALID_FLAG_DIGIT) && c_isdigit (str[i])) ||
      (extra && strchr (extra, str[i]));

    if (!valid_char) return false;
  }

  return true;
}

#if 0 /* not used yet */
/**
 * Hint that we will read or write the file descriptor normally.
 *
 * On Linux, this clears the C<FMODE_RANDOM> flag on the file [see
 * below] and sets the per-file number of readahead pages to equal the
 * block device readahead setting.
 *
 * It's OK to call this on a non-file since we ignore failure as it is
 * only a hint.
 */
void
guestfs_int_fadvise_normal (int fd)
{
#if defined(HAVE_POSIX_FADVISE) && defined(POSIX_FADV_NORMAL)
  /* It's not clear from the man page, but the 'advice' parameter is
   * NOT a bitmask.  You can only pass one parameter with each call.
   */
  ignore_value (posix_fadvise (fd, 0, 0, POSIX_FADV_NORMAL));
#endif
}
#endif

/**
 * Hint that we will read or write the file descriptor sequentially.
 *
 * On Linux, this clears the C<FMODE_RANDOM> flag on the file [see
 * below] and sets the per-file number of readahead pages to twice the
 * block device readahead setting.
 *
 * It's OK to call this on a non-file since we ignore failure as it is
 * only a hint.
 */
void
guestfs_int_fadvise_sequential (int fd)
{
#if defined(HAVE_POSIX_FADVISE) && defined(POSIX_FADV_SEQUENTIAL)
  /* It's not clear from the man page, but the 'advice' parameter is
   * NOT a bitmask.  You can only pass one parameter with each call.
   */
  ignore_value (posix_fadvise (fd, 0, 0, POSIX_FADV_SEQUENTIAL));
#endif
}

/**
 * Hint that we will read or write the file descriptor randomly.
 *
 * On Linux, this sets the C<FMODE_RANDOM> flag on the file.  The
 * effect of this flag is to:
 *
 * =over 4
 *
 * =item *
 *
 * Disable normal sequential file readahead.
 *
 * =item *
 *
 * If any read of the file is done which misses in the page cache, 2MB
 * are read into the page cache.  [I think - I'm not sure I totally
 * understand what this is doing]
 *
 * =back
 *
 * It's OK to call this on a non-file since we ignore failure as it is
 * only a hint.
 */
void
guestfs_int_fadvise_random (int fd)
{
#if defined(HAVE_POSIX_FADVISE) && defined(POSIX_FADV_RANDOM)
  /* It's not clear from the man page, but the 'advice' parameter is
   * NOT a bitmask.  You can only pass one parameter with each call.
   */
  ignore_value (posix_fadvise (fd, 0, 0, POSIX_FADV_RANDOM));
#endif
}

/**
 * Hint that we will access the data only once.
 *
 * On Linux, this does nothing.
 *
 * It's OK to call this on a non-file since we ignore failure as it is
 * only a hint.
 */
void
guestfs_int_fadvise_noreuse (int fd)
{
#if defined(HAVE_POSIX_FADVISE) && defined(POSIX_FADV_NOREUSE)
  /* It's not clear from the man page, but the 'advice' parameter is
   * NOT a bitmask.  You can only pass one parameter with each call.
   */
  ignore_value (posix_fadvise (fd, 0, 0, POSIX_FADV_NOREUSE));
#endif
}

#if 0 /* not used yet */
/**
 * Hint that we will not access the data in the near future.
 *
 * On Linux, this immediately writes out any dirty pages in the page
 * cache and then invalidates (drops) all pages associated with this
 * file from the page cache.  Apparently it does this even if the file
 * is opened or being used by other processes.  This setting is not
 * persistent; if you subsequently read the file it will be cached in
 * the page cache as normal.
 *
 * It's OK to call this on a non-file since we ignore failure as it is
 * only a hint.
 */
void
guestfs_int_fadvise_dontneed (int fd)
{
#if defined(HAVE_POSIX_FADVISE) && defined(POSIX_FADV_DONTNEED)
  /* It's not clear from the man page, but the 'advice' parameter is
   * NOT a bitmask.  You can only pass one parameter with each call.
   */
  ignore_value (posix_fadvise (fd, 0, 0, POSIX_FADV_DONTNEED));
#endif
}
#endif

#if 0 /* not used yet */
/**
 * Hint that we will access the data in the near future.
 *
 * On Linux, this immediately reads the whole file into the page
 * cache.  This setting is not persistent; subsequently pages may be
 * dropped from the page cache as normal.
 *
 * It's OK to call this on a non-file since we ignore failure as it is
 * only a hint.
 */
void
guestfs_int_fadvise_willneed (int fd)
{
#if defined(HAVE_POSIX_FADVISE) && defined(POSIX_FADV_WILLNEED)
  /* It's not clear from the man page, but the 'advice' parameter is
   * NOT a bitmask.  You can only pass one parameter with each call.
   */
  ignore_value (posix_fadvise (fd, 0, 0, POSIX_FADV_WILLNEED));
#endif
}
#endif

/**
 * Unquote a shell-quoted string.
 *
 * Augeas passes strings to us which may be quoted, eg. if they come
 * from files in F</etc/sysconfig>.  This function can do simple
 * unquoting of these strings.
 *
 * Note this function does not do variable substitution, since that is
 * impossible without knowing the file context and indeed the
 * environment under which the shell script is run.  Configuration
 * files should not use complex quoting.
 *
 * C<str> is the input string from Augeas, a string that may be
 * single- or double-quoted or may not be quoted.  The returned string
 * is unquoted, and must be freed by the caller.  C<NULL> is returned
 * on error and C<errno> is set accordingly.
 *
 * For information on double-quoting in bash, see
 * L<https://www.gnu.org/software/bash/manual/html_node/Double-Quotes.html>
 */
char *
guestfs_int_shell_unquote (const char *str)
{
  size_t len = strlen (str);
  char *ret;

  if (len >= 2) {
    if (str[0] == '\'' && str[len-1] == '\'') {
                                /* single quoting */
      ret = strndup (&str[1], len-2);
      if (ret == NULL)
        return NULL;
      return ret;
    }
    else if (str[0] == '"' && str[len-1] == '"') {
                                /* double quoting */
      size_t i, j;

      ret = malloc (len + 1);   /* strings always get smaller */
      if (ret == NULL)
        return NULL;

      for (i = 1, j = 0; i < len-1 /* ignore final quote */; ++i, ++j) {
        if (i < len-2 /* ignore final char before final quote */ &&
            str[i] == '\\' &&
            (str[i+1] == '$' || str[i+1] == '`' || str[i+1] == '"' ||
             str[i+1] == '\\' || str[i+1] == '\n'))
          ++i;
        ret[j] = str[i];
      }

      ret[j] = '\0';

      return ret;
    }
  }

  return strdup (str);
}
