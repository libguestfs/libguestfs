/* libguestfs
 * Copyright (C) 2009-2019 Red Hat Inc.
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
 * Mini-library for writing qemu command lines and qemu config files.
 *
 * There are some shortcomings with the model used for qemu options
 * which aren't clear until you try to convert options into a
 * configuration file.  However if we attempted to model the options
 * in more detail then this library would be both very difficult to
 * use and incompatible with older versions of qemu.  Hopefully the
 * current model is a decent compromise.
 *
 * For reference here are the problems:
 *
 * =over 4
 *
 * =item *
 *
 * There's inconsistency in qemu between options and config file, eg.
 * C<-smp 4> becomes:
 *
 *  [smp-opts]
 *    cpus = "4"
 *
 * =item *
 *
 * Similar to the previous point, you can write either C<-smp 4> or
 * C<-smp cpus=4> (although this won't work in very old qemu).  When
 * generating a config file you need to know the implicit key name.
 *
 * =item *
 *
 * In C<-opt key=value,...> the C<key> is really a tree/array
 * specifier.  The way this works is complicated but hinted at
 * here:
 * L<http://git.qemu.org/?p=qemu.git;a=blob;f=util/keyval.c;h=93d5db6b590427e412dfb172f1c406d6dd8958c1;hb=HEAD>
 *
 * =item *
 *
 * Some options are syntactic sugar.  eg. C<-kernel foo> is sugar
 * for C<-machine kernel=foo>.
 *
 * =back
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <assert.h>
#include <errno.h>
#include <sys/stat.h>

#include "qemuopts.h"

enum qopt_type {
  QOPT_FLAG,
  QOPT_ARG,
  QOPT_ARG_NOQUOTE,
  QOPT_ARG_LIST,
};

struct qopt {
  enum qopt_type type;
  char *flag;             /* eg. "-m" */
  char *value;            /* Value, for QOPT_ARG, QOPT_ARG_NOQUOTE. */
  char **values;          /* List of values, for QOPT_ARG_LIST. */
};

struct qemuopts {
  char *binary;        /* NULL = qemuopts_set_binary not called yet */
  struct qopt *options;
  size_t nr_options, nr_alloc;
};

/**
 * Create an empty list of qemu options.
 *
 * The caller must eventually free the list by calling
 * C<qemuopts_free>.
 *
 * Returns C<NULL> on error, setting C<errno>.
 */
struct qemuopts *
qemuopts_create (void)
{
  struct qemuopts *qopts;

  qopts = malloc (sizeof *qopts);
  if (qopts == NULL)
    return NULL;

  qopts->binary = NULL;
  qopts->options = NULL;
  qopts->nr_options = qopts->nr_alloc = 0;

  return qopts;
}

static void
free_string_list (char **argv)
{
  size_t i;

  if (argv == NULL)
    return;

  for (i = 0; argv[i] != NULL; ++i)
    free (argv[i]);
  free (argv);
}

static size_t
count_strings (char **argv)
{
  size_t i;

  for (i = 0; argv[i] != NULL; ++i)
    ;
  return i;
}

/**
 * Free the list of qemu options.
 */
void
qemuopts_free (struct qemuopts *qopts)
{
  size_t i;

  for (i = 0; i < qopts->nr_options; ++i) {
    free (qopts->options[i].flag);
    free (qopts->options[i].value);
    free_string_list (qopts->options[i].values);
  }
  free (qopts->options);
  free (qopts->binary);
  free (qopts);
}

static struct qopt *
extend_options (struct qemuopts *qopts)
{
  struct qopt *new_options;
  struct qopt *ret;

  if (qopts->nr_options >= qopts->nr_alloc) {
    if (qopts->nr_alloc == 0)
      qopts->nr_alloc = 1;
    else
      qopts->nr_alloc *= 2;
    new_options = realloc (qopts->options,
                           qopts->nr_alloc * sizeof (struct qopt));
    if (new_options == NULL)
      return NULL;
    qopts->options = new_options;
  }

  ret = &qopts->options[qopts->nr_options];
  qopts->nr_options++;

  ret->type = 0;
  ret->flag = NULL;
  ret->value = NULL;
  ret->values = NULL;

  return ret;
}

static struct qopt *
last_option (struct qemuopts *qopts)
{
  assert (qopts->nr_options > 0);
  return &qopts->options[qopts->nr_options-1];
}

/**
 * Add a command line flag which has no argument. eg:
 *
 *  qemuopts_add_flag (qopts, "-no-user-config");
 *
 * Returns C<0> on success.  Returns C<-1> on error, setting C<errno>.
 */
int
qemuopts_add_flag (struct qemuopts *qopts, const char *flag)
{
  struct qopt *qopt;
  char *flag_copy;

  if (flag[0] != '-') {
    errno = EINVAL;
    return -1;
  }

  flag_copy = strdup (flag);
  if (flag_copy == NULL)
    return -1;

  if ((qopt = extend_options (qopts)) == NULL) {
    free (flag_copy);
    return -1;
  }

  qopt->type = QOPT_FLAG;
  qopt->flag = flag_copy;
  return 0;
}

/**
 * Add a command line flag which has a single argument. eg:
 *
 *  qemuopts_add_arg (qopts, "-m", "1024");
 *
 * Don't use this if the argument is a comma-separated list, since
 * quoting will not be done properly.  See C<qemuopts_add_arg_list>.
 *
 * Returns C<0> on success.  Returns C<-1> on error, setting C<errno>.
 */
int
qemuopts_add_arg (struct qemuopts *qopts, const char *flag, const char *value)
{
  struct qopt *qopt;
  char *flag_copy;
  char *value_copy;

  if (flag[0] != '-') {
    errno = EINVAL;
    return -1;
  }

  flag_copy = strdup (flag);
  if (flag_copy == NULL)
    return -1;

  value_copy = strdup (value);
  if (value_copy == NULL) {
    free (flag_copy);
    return -1;
  }

  if ((qopt = extend_options (qopts)) == NULL) {
    free (flag_copy);
    free (value_copy);
    return -1;
  }

  qopt->type = QOPT_ARG;
  qopt->flag = flag_copy;
  qopt->value = value_copy;
  return 0;
}

/**
 * Add a command line flag which has a single formatted argument. eg:
 *
 *  qemuopts_add_arg_format (qopts, "-m", "%d", 1024);
 *
 * Don't use this if the argument is a comma-separated list, since
 * quoting will not be done properly.  See C<qemuopts_add_arg_list>.
 *
 * Returns C<0> on success.  Returns C<-1> on error, setting C<errno>.
 */
int
qemuopts_add_arg_format (struct qemuopts *qopts, const char *flag,
                         const char *fs, ...)
{
  char *value;
  int r;
  va_list args;

  if (flag[0] != '-') {
    errno = EINVAL;
    return -1;
  }

  va_start (args, fs);
  r = vasprintf (&value, fs, args);
  va_end (args);
  if (r == -1)
    return -1;

  r = qemuopts_add_arg (qopts, flag, value);
  free (value);
  return r;
}

/**
 * This is like C<qemuopts_add_arg> except that no quoting is done on
 * the value.
 *
 * For C<qemuopts_to_script> and C<qemuopts_to_channel>, this
 * means that neither shell quoting nor qemu comma quoting is done
 * on the value.
 *
 * For C<qemuopts_to_argv> this means that qemu comma quoting is
 * not done.
 *
 * C<qemuopts_to_config*> will fail.
 *
 * You should use this with great care.
 */
int
qemuopts_add_arg_noquote (struct qemuopts *qopts, const char *flag,
                          const char *value)
{
  struct qopt *qopt;
  char *flag_copy;
  char *value_copy;

  if (flag[0] != '-') {
    errno = EINVAL;
    return -1;
  }

  flag_copy = strdup (flag);
  if (flag_copy == NULL)
    return -1;

  value_copy = strdup (value);
  if (value_copy == NULL) {
    free (flag_copy);
    return -1;
  }

  if ((qopt = extend_options (qopts)) == NULL) {
    free (flag_copy);
    free (value_copy);
    return -1;
  }

  qopt->type = QOPT_ARG_NOQUOTE;
  qopt->flag = flag_copy;
  qopt->value = value_copy;
  return 0;
}

/**
 * Start an argument that takes a comma-separated list of fields.
 *
 * Typical usage is like this (with error handling omitted):
 *
 *  qemuopts_start_arg_list (qopts, "-drive");
 *  qemuopts_append_arg_list (qopts, "file=foo");
 *  qemuopts_append_arg_list_format (qopts, "if=%s", "ide");
 *  qemuopts_end_arg_list (qopts);
 *
 * which would construct C<-drive file=foo,if=ide>
 *
 * See also C<qemuopts_add_arg_list> for a way to do simple cases in
 * one call.
 *
 * Returns C<0> on success.  Returns C<-1> on error, setting C<errno>.
 */
int
qemuopts_start_arg_list (struct qemuopts *qopts, const char *flag)
{
  struct qopt *qopt;
  char *flag_copy;
  char **values;

  if (flag[0] != '-') {
    errno = EINVAL;
    return -1;
  }

  flag_copy = strdup (flag);
  if (flag_copy == NULL)
    return -1;

  values = calloc (1, sizeof (char *));
  if (values == NULL) {
    free (flag_copy);
    return -1;
  }

  if ((qopt = extend_options (qopts)) == NULL) {
    free (flag_copy);
    free (values);
    return -1;
  }

  qopt->type = QOPT_ARG_LIST;
  qopt->flag = flag_copy;
  qopt->values = values;
  return 0;
}

int
qemuopts_append_arg_list (struct qemuopts *qopts, const char *value)
{
  struct qopt *qopt;
  char **new_values;
  char *value_copy;
  size_t len;

  qopt = last_option (qopts);
  assert (qopt->type == QOPT_ARG_LIST);
  len = count_strings (qopt->values);

  value_copy = strdup (value);
  if (value_copy == NULL)
    return -1;

  new_values = realloc (qopt->values, (len+2) * sizeof (char *));
  if (new_values == NULL) {
    free (value_copy);
    return -1;
  }
  qopt->values = new_values;
  qopt->values[len] = value_copy;
  qopt->values[len+1] = NULL;
  return 0;
}

int
qemuopts_append_arg_list_format (struct qemuopts *qopts,
                                 const char *fs, ...)
{
  char *value;
  int r;
  va_list args;

  va_start (args, fs);
  r = vasprintf (&value, fs, args);
  va_end (args);
  if (r == -1)
    return -1;

  r = qemuopts_append_arg_list (qopts, value);
  free (value);
  return r;
}

int
qemuopts_end_arg_list (struct qemuopts *qopts)
{
  struct qopt *qopt;
  size_t len;

  qopt = last_option (qopts);
  assert (qopt->type == QOPT_ARG_LIST);
  len = count_strings (qopt->values);
  if (len == 0)
    return -1;

  return 0;
}

/**
 * Add a command line flag which has a list of arguments. eg:
 *
 *  qemuopts_add_arg_list (qopts, "-drive", "file=foo", "if=ide", NULL);
 *
 * This is turned into a comma-separated list, like:
 * C<-drive file=foo,if=ide>.  Note that this handles qemu quoting
 * properly, so individual elements may contain commas and this will
 * do the right thing.
 *
 * Returns C<0> on success.  Returns C<-1> on error, setting C<errno>.
 */
int
qemuopts_add_arg_list (struct qemuopts *qopts, const char *flag,
                       const char *elem0, ...)
{
  va_list args;
  const char *elem;

  if (qemuopts_start_arg_list (qopts, flag) == -1)
    return -1;
  if (qemuopts_append_arg_list (qopts, elem0) == -1)
    return -1;
  va_start (args, elem0);
  elem = va_arg (args, const char *);
  while (elem != NULL) {
    if (qemuopts_append_arg_list (qopts, elem) == -1) {
      va_end (args);
      return -1;
    }
    elem = va_arg (args, const char *);
  }
  va_end (args);
  if (qemuopts_end_arg_list (qopts) == -1)
    return -1;
  return 0;
}

/**
 * Set the qemu binary name.
 *
 * Returns C<0> on success.  Returns C<-1> on error, setting C<errno>.
 */
int
qemuopts_set_binary (struct qemuopts *qopts, const char *binary)
{
  char *binary_copy;

  binary_copy = strdup (binary);
  if (binary_copy == NULL)
    return -1;

  free (qopts->binary);
  qopts->binary = binary_copy;
  return 0;
}

/**
 * Set the qemu binary name to C<qemu-system-[arch]>.
 *
 * As a special case if C<arch> is C<NULL>, the binary is set to the
 * KVM binary for the current host architecture:
 *
 *  qemuopts_set_binary_by_arch (qopts, NULL);
 *
 * Returns C<0> on success.  Returns C<-1> on error, setting C<errno>.
 */
int
qemuopts_set_binary_by_arch (struct qemuopts *qopts, const char *arch)
{
  char *binary;

  free (qopts->binary);
  qopts->binary = NULL;

  if (arch) {
    if (asprintf (&binary, "qemu-system-%s", arch) == -1)
      return -1;
    qopts->binary = binary;
  }
  else {
#if defined(__i386__) || defined(__x86_64__)
    binary = strdup ("qemu-system-x86_64");
#elif defined(__aarch64__)
    binary = strdup ("qemu-system-aarch64");
#elif defined(__arm__)
    binary = strdup ("qemu-system-arm");
#elif defined(__powerpc64__)
    binary = strdup ("qemu-system-ppc64");
#elif defined(__s390x__)
    binary = strdup ("qemu-system-s390x");
#else
    /* There is no KVM capability on this architecture. */
    errno = ENXIO;
    binary = NULL;
#endif
    if (binary == NULL)
      return -1;
    qopts->binary = binary;
  }

  return 0;
}

/**
 * Write the qemu options to a script.
 *
 * C<qemuopts_set_binary*> must be called first.
 *
 * The script file will start with C<#!/bin/sh> and will be chmod to
 * mode C<0755>.
 *
 * Returns C<0> on success.  Returns C<-1> on error, setting C<errno>.
 */
int
qemuopts_to_script (struct qemuopts *qopts, const char *filename)
{
  FILE *fp;
  int saved_errno;

  fp = fopen (filename, "w");
  if (fp == NULL)
    return -1;

  fprintf (fp, "#!/bin/sh -\n\n");
  if (qemuopts_to_channel (qopts, fp) == -1) {
  error:
    saved_errno = errno;
    fclose (fp);
    unlink (filename);
    errno = saved_errno;
    return -1;
  }

  if (fchmod (fileno (fp), 0755) == -1)
    goto error;

  if (fclose (fp) == EOF) {
    saved_errno = errno;
    unlink (filename);
    errno = saved_errno;
    return -1;
  }

  return 0;
}

/**
 * Print C<str> to C<fp>, shell-quoting it if necessary.
 */
static void
shell_quote (const char *str, FILE *fp)
{
  const char *safe_chars =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_=,:/";
  size_t i, len;

  /* If the string consists only of safe characters, output it as-is. */
  len = strlen (str);
  if (len == strspn (str, safe_chars)) {
    fputs (str, fp);
    return;
  }

  /* Double-quote the string. */
  fputc ('"', fp);
  for (i = 0; i < len; ++i) {
    switch (str[i]) {
    case '$': case '`': case '\\': case '"':
      fputc ('\\', fp);
      /*FALLTHROUGH*/
    default:
      fputc (str[i], fp);
    }
  }
  fputc ('"', fp);
}

/**
 * Print C<str> to C<fp> doing both shell and qemu comma quoting.
 */
static void
shell_and_comma_quote (const char *str, FILE *fp)
{
  const char *safe_chars =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_=:/";
  size_t i, len;

  /* If the string consists only of safe characters, output it as-is. */
  len = strlen (str);
  if (len == strspn (str, safe_chars)) {
    fputs (str, fp);
    return;
  }

  fputc ('"', fp);
  for (i = 0; i < len; ++i) {
    switch (str[i]) {
    case ',':
      /* qemu comma-quoting doubles commas. */
      fputs (",,", fp);
      break;
    case '$': case '`': case '\\': case '"':
      fputc ('\\', fp);
      /*FALLTHROUGH*/
    default:
      fputc (str[i], fp);
    }
  }
  fputc ('"', fp);
}

/**
 * Write the qemu options to a C<FILE *fp>.
 *
 * C<qemuopts_set_binary*> must be called first.
 *
 * Only the qemu command line is written.  The caller may need to add
 * C<#!/bin/sh> and may need to chmod the resulting file to C<0755>.
 *
 * Returns C<0> on success.  Returns C<-1> on error, setting C<errno>.
 */
int
qemuopts_to_channel (struct qemuopts *qopts, FILE *fp)
{
  size_t i, j;
  const char *nl = " \\\n    ";

  if (qopts->binary == NULL) {
    errno = ENOENT;
    return -1;
  }

  shell_quote (qopts->binary, fp);
  for (i = 0; i < qopts->nr_options; ++i) {
    switch (qopts->options[i].type) {
    case QOPT_FLAG:
      fprintf (fp, "%s%s", nl, qopts->options[i].flag);
      break;

    case QOPT_ARG_NOQUOTE:
      fprintf (fp, "%s%s %s",
               nl, qopts->options[i].flag, qopts->options[i].value);
      break;

    case QOPT_ARG:
      fprintf (fp, "%s%s ",
               nl, qopts->options[i].flag);
      shell_and_comma_quote (qopts->options[i].value, fp);
      break;

    case QOPT_ARG_LIST:
      fprintf (fp, "%s%s ",
               nl, qopts->options[i].flag);
      for (j = 0; qopts->options[i].values[j] != NULL; ++j) {
        if (j > 0) fputc (',', fp);
        shell_and_comma_quote (qopts->options[i].values[j], fp);
      }
      break;
    }
  }
  fputc ('\n', fp);

  return 0;
}

/**
 * Return a NULL-terminated argument list, of the kind that can be
 * passed directly to L<execv(3)>.
 *
 * C<qemuopts_set_binary*> must be called first.  It will be
 * returned as C<argv[0]> in the returned list.
 *
 * The list of strings and the strings themselves must be freed by the
 * caller.
 *
 * Returns C<NULL> on error, setting C<errno>.
 */
char **
qemuopts_to_argv (struct qemuopts *qopts)
{
  char **ret, **values;
  size_t n, i, j, k, len;

  if (qopts->binary == NULL) {
    errno = ENOENT;
    return NULL;
  }

  /* Count how many arguments we will return.  It's not the same as
   * the number of options because some options are flags (returning a
   * single string) and others have a parameter (two strings).
   */
  n = 1; /* for the qemu binary */
  for (i = 0; i < qopts->nr_options; ++i) {
    switch (qopts->options[i].type) {
    case QOPT_FLAG:
      n++;
      break;

    case QOPT_ARG_NOQUOTE:
    case QOPT_ARG:
    case QOPT_ARG_LIST:
      n += 2;
    }
  }

  ret = calloc (n+1, sizeof (char *));
  if (ret == NULL)
    return NULL;

  n = 0;
  ret[n] = strdup (qopts->binary);
  if (ret[n] == NULL) {
  error:
    for (i = 0; i < n; ++i)
      free (ret[i]);
    free (ret);
    return NULL;
  }
  n++;

  for (i = 0; i < qopts->nr_options; ++i) {
    ret[n] = strdup (qopts->options[i].flag);
    if (ret[n] == NULL) goto error;
    n++;

    switch (qopts->options[i].type) {
    case QOPT_FLAG:
      /* nothing */
      break;

    case QOPT_ARG_NOQUOTE:
      ret[n] = strdup (qopts->options[i].value);
      if (ret[n] == NULL) goto error;
      n++;
      break;

    case QOPT_ARG:
      /* We only have to do comma-quoting here. */
      len = 0;
      for (k = 0; k < strlen (qopts->options[i].value); ++k) {
        if (qopts->options[i].value[k] == ',') len++;
        len++;
      }
      ret[n] = malloc (len+1);
      if (ret[n] == NULL) goto error;
      len = 0;
      for (k = 0; k < strlen (qopts->options[i].value); ++k) {
        if (qopts->options[i].value[k] == ',') ret[n][len++] = ',';
        ret[n][len++] = qopts->options[i].value[k];
      }
      ret[n][len] = '\0';
      n++;
      break;

    case QOPT_ARG_LIST:
      /* We only have to do comma-quoting here. */
      values = qopts->options[i].values;
      len = count_strings (values);
      assert (len > 0);
      len -= 1 /* one for each comma */;
      for (j = 0; values[j] != NULL; ++j) {
        for (k = 0; k < strlen (values[j]); ++k) {
          if (values[j][k] == ',') len++;
          len++;
        }
      }
      ret[n] = malloc (len+1);
      if (ret[n] == NULL) goto error;
      len = 0;
      for (j = 0; values[j] != NULL; ++j) {
        if (j > 0) ret[n][len++] = ',';
        for (k = 0; k < strlen (values[j]); ++k) {
          if (values[j][k] == ',') ret[n][len++] = ',';
          ret[n][len++] = values[j][k];
        }
      }
      ret[n][len] = '\0';
      n++;
    }
  }

  return ret;
}

/**
 * Write the qemu options to a qemu config file, suitable for reading
 * in using C<qemu -readconfig filename>.
 *
 * Note that qemu config files have limitations on content and
 * quoting, so not all qemuopts structs can be written (this function
 * returns an error in these cases).  For more information see
 * L<https://habkost.net/posts/2016/12/qemu-apis-qemuopts.html>
 * L<https://bugs.launchpad.net/qemu/+bug/1686364>
 *
 * Also, command line argument names and config file sections
 * sometimes have different names.  For example the equivalent of
 * C<-m 1024> is:
 *
 *  [memory]
 *    size = "1024"
 *
 * This code does I<not> attempt to convert between the two forms.
 * You just need to know how to do that yourself.
 *
 * Returns C<0> on success.  Returns C<-1> on error, setting C<errno>.
 */
int
qemuopts_to_config_file (struct qemuopts *qopts, const char *filename)
{
  FILE *fp;
  int saved_errno;

  fp = fopen (filename, "w");
  if (fp == NULL)
    return -1;

  if (qemuopts_to_config_channel (qopts, fp) == -1) {
    saved_errno = errno;
    fclose (fp);
    unlink (filename);
    errno = saved_errno;
    return -1;
  }

  if (fclose (fp) == EOF) {
    saved_errno = errno;
    unlink (filename);
    errno = saved_errno;
    return -1;
  }

  return 0;
}

/**
 * Same as C<qemuopts_to_config_file>, but this writes to a C<FILE *fp>.
 */
int
qemuopts_to_config_channel (struct qemuopts *qopts, FILE *fp)
{
  size_t i, j, k;
  ssize_t id_param;
  char **values;

  /* Before starting, try to detect some illegal options which
   * cannot be translated into a qemu config file.
   */
  for (i = 0; i < qopts->nr_options; ++i) {
    switch (qopts->options[i].type) {
    case QOPT_FLAG:
      /* Single flags cannot be written to a config file.  It seems
       * as if the file format simply does not support this notion.
       */
      errno = EINVAL;
      return -1;

    case QOPT_ARG_NOQUOTE:
      /* arg_noquote is incompatible with this function. */
      errno = EINVAL;
      return -1;

    case QOPT_ARG:
      /* Single arguments can be expressed, but we would have to do
       * special translation as outlined in the description of
       * C<qemuopts_to_config_file> above.
       */
      errno = EINVAL;
      return -1;

    case QOPT_ARG_LIST:
      /* If any value contains a double quote character, then qemu
       * cannot parse it.  See
       * https://bugs.launchpad.net/qemu/+bug/1686364.
       */
      values = qopts->options[i].values;
      for (j = 0; values[j] != NULL; ++j) {
        if (strchr (values[j], '"') != NULL) {
          errno = EINVAL;
          return -1;
        }
      }
      break;
    }
  }

  /* Write the output. */
  fprintf (fp, "# qemu config file\n\n");

  for (i = 0; i < qopts->nr_options; ++i) {
    switch (qopts->options[i].type) {
    case QOPT_FLAG:
    case QOPT_ARG_NOQUOTE:
    case QOPT_ARG:
      abort ();

    case QOPT_ARG_LIST:
      values = qopts->options[i].values;
      /* The id=... parameter is special. */
      id_param = -1;
      for (j = 0; values[j] != NULL; ++j) {
        if (strncmp (values[j], "id=", 2) == 0) {
          id_param = j;
          break;
        }
      }

      if (id_param >= 0)
        fprintf (fp, "[%s \"%s\"]\n",
                 &qopts->options[i].flag[1],
                 &values[id_param][3]);
      else
        fprintf (fp, "[%s]\n", &qopts->options[i].flag[1]);

      for (j = 0; values[j] != NULL; ++j) {
        if ((ssize_t) j != id_param) {
          k = strcspn (values[j], "=");
          if (k < strlen (values[j])) {
            fprintf (fp, "  %.*s = ", (int) k, values[j]);
            fprintf (fp, "\"%s\"\n", &values[j][k+1]);
          }
          else
            fprintf (fp, "  %s = \"on\"\n", values[j]);
        }
      }
    }
    fprintf (fp, "\n");
  }

  return 0;
}
