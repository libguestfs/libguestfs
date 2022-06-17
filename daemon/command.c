/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2015 Red Hat Inc.
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

/**
 * This file contains a number of useful functions for running
 * external commands and capturing their output.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <error.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include "ignore-value.h"

#include "guestfs-internal-all.h"
#include "command.h"
#include "cleanups.h"

extern int verbose;

extern const char *sysroot;
extern size_t sysroot_len;

/* For improved readability dealing with pipe arrays */
#define PIPE_READ 0
#define PIPE_WRITE 1

/**
 * Run a command.  Optionally capture stdout and stderr as strings.
 *
 * Returns C<0> if the command ran successfully, or C<-1> if there was
 * any error.
 *
 * For a description of the C<flags> see C<commandrvf>.
 *
 * There is also a macro C<command(out,err,name,...)> which calls
 * C<commandf> with C<flags=0>.
 */
int
commandf (char **stdoutput, char **stderror, unsigned flags,
          const char *name, ...)
{
  va_list args;
  /* NB: Mustn't free the strings which are on the stack. */
  CLEANUP_FREE const char **argv = NULL;
  char *s;
  size_t i;
  int r;

  /* Collect the command line arguments into an array. */
  i = 2;
  argv = malloc (sizeof (char *) * i);
  if (argv == NULL) {
    perror ("malloc");
    return -1;
  }
  argv[0] = (char *) name;
  argv[1] = NULL;

  va_start (args, name);

  while ((s = va_arg (args, char *)) != NULL) {
    const char **p = realloc (argv, sizeof (char *) * (++i));
    if (p == NULL) {
      perror ("realloc");
      va_end (args);
      return -1;
    }
    argv = p;
    argv[i-2] = s;
    argv[i-1] = NULL;
  }

  va_end (args);

  r = commandvf (stdoutput, stderror, flags, (const char * const*) argv);

  return r;
}

/**
 * Same as C<command>, but we allow the status code from the
 * subcommand to be non-zero, and return that status code.
 *
 * We still return C<-1> if there was some other error.
 *
 * There is also a macro C<commandr(out,err,name,...)> which calls
 * C<commandrf> with C<flags=0>.
 */
int
commandrf (char **stdoutput, char **stderror, unsigned flags,
           const char *name, ...)
{
  va_list args;
  CLEANUP_FREE const char **argv = NULL;
  char *s;
  int i, r;

  /* Collect the command line arguments into an array. */
  i = 2;
  argv = malloc (sizeof (char *) * i);
  if (argv == NULL) {
    perror ("malloc");
    return -1;
  }
  argv[0] = (char *) name;
  argv[1] = NULL;

  va_start (args, name);

  while ((s = va_arg (args, char *)) != NULL) {
    const char **p = realloc (argv, sizeof (char *) * (++i));
    if (p == NULL) {
      perror ("realloc");
      va_end (args);
      return -1;
    }
    argv = p;
    argv[i-2] = s;
    argv[i-1] = NULL;
  }

  va_end (args);

  r = commandrvf (stdoutput, stderror, flags, argv);

  return r;
}

/**
 * Same as C<command>, but passing in an argv array.
 *
 * There is also a macro C<commandv(out,err,argv)> which calls
 * C<commandvf> with C<flags=0>.
 */
int
commandvf (char **stdoutput, char **stderror, unsigned flags,
           char const *const *argv)
{
  int r;

  r = commandrvf (stdoutput, stderror, flags, (void *) argv);
  if (r == 0)
    return 0;
  else
    return -1;
}

/**
 * This is a more sane version of L<system(3)> for running external
 * commands.  It uses fork/execvp, so we don't need to worry about
 * quoting of parameters, and it allows us to capture any error
 * messages in a buffer.
 *
 * If C<stdoutput> is not C<NULL>, then C<*stdoutput> will return the
 * stdout of the command as a string.
 *
 * If C<stderror> is not C<NULL>, then C<*stderror> will return the
 * stderr of the command.  If there is a final \n character, it is
 * removed so you can use the error string directly in a call to
 * C<reply_with_error>.
 *
 * Flags are:
 *
 * =over 4
 *
 * =item C<COMMAND_FLAG_FOLD_STDOUT_ON_STDERR>
 *
 * For broken external commands that send error messages to stdout
 * (hello, parted) but that don't have any useful stdout information,
 * use this flag to capture the error messages in the C<*stderror>
 * buffer.  If using this flag, you should pass C<stdoutput=NULL>
 * because nothing could ever be captured in that buffer.
 *
 * =item C<COMMAND_FLAG_CHROOT_COPY_FILE_TO_STDIN>
 *
 * For running external commands on chrooted files correctly (see
 * L<https://bugzilla.redhat.com/579608>) specifying this flag causes
 * another process to be forked which chroots into sysroot and just
 * copies the input file to stdin of the specified command.  The file
 * descriptor is ORed with the flags, and that file descriptor is
 * always closed by this function.  See F<daemon/hexdump.c> for an
 * example of usage.
 *
 * =back
 *
 * There is also a macro C<commandrv(out,err,argv)> which calls
 * C<commandrvf> with C<flags=0>.
 */
int
commandrvf (char **stdoutput, char **stderror, unsigned flags,
            char const* const *argv)
{
  size_t so_size = 0, se_size = 0;
  int so_fd[2], se_fd[2];
  const unsigned flag_copy_stdin =
    flags & COMMAND_FLAG_CHROOT_COPY_FILE_TO_STDIN;
  const int flag_copy_fd = (int) (flags & COMMAND_FLAG_FD_MASK);
  const unsigned flag_out_on_err = flags & COMMAND_FLAG_FOLD_STDOUT_ON_STDERR;
  pid_t pid;
  int r, quit, i;
  fd_set rset, rset2;
  char buf[256];
  char *p;

  if (stdoutput) *stdoutput = NULL;
  if (stderror) *stderror = NULL;

  if (verbose) {
    printf ("commandrvf: stdout=%s stderr=%s flags=0x%x\n",
            stdoutput ? "y" : flag_out_on_err ? "e" : "n",
            stderror ? "y" : "n", flags);
    fputs ("commandrvf: ", stdout);
    fputs (argv[0], stdout);
    for (i = 1; argv[i] != NULL; ++i) {
      char quote;

      /* Do simple (and incorrect) quoting of the debug output.  Real
       * quoting is not necessary because we use execvp to run the
       * command below.
       */
      if (strchr (argv[i], '\''))
        quote = '"';
      else if (strchr (argv[i], '"'))
        quote = '\'';
      else if (strchr (argv[i], ' '))
        quote = '"';
      else
        quote = 0;

      putchar (' ');
      if (quote) putchar (quote);
      fputs (argv[i], stdout);
      if (quote) putchar (quote);
    }
    putchar ('\n');
  }

  /* Note: abort is used in a few places along the error paths early
   * in this function.  This is because (a) cleaning up correctly is
   * very complex at these places and (b) abort is used when a
   * resource problems is indicated which would be due to much more
   * serious issues - eg. memory or file descriptor leaks.  We
   * wouldn't expect fork(2) or pipe(2) to fail in normal
   * circumstances.
   */

  if (pipe (so_fd) == -1 || pipe (se_fd) == -1) {
    error (0, errno, "pipe");
    abort ();
  }

  pid = fork ();
  if (pid == -1) {
    error (0, errno, "fork");
    abort ();
  }

  if (pid == 0) {		/* Child process running the command. */
    signal (SIGALRM, SIG_DFL);
    signal (SIGPIPE, SIG_DFL);
    close (0);
    if (flag_copy_stdin) {
      if (dup2 (flag_copy_fd, STDIN_FILENO) == -1) {
        perror ("dup2/flag_copy_fd");
        _exit (EXIT_FAILURE);
      }
    } else {
      /* Set stdin to /dev/null. */
      if (open ("/dev/null", O_RDONLY) == -1) {
        perror ("open: /dev/null");
        _exit (EXIT_FAILURE);
      }
    }
    close (so_fd[PIPE_READ]);
    close (se_fd[PIPE_READ]);
    if (!flag_out_on_err) {
      if (dup2 (so_fd[PIPE_WRITE], STDOUT_FILENO) == -1) {
        perror ("dup2/so_fd[PIPE_WRITE]");
        _exit (EXIT_FAILURE);
      }
    } else {
      if (dup2 (se_fd[PIPE_WRITE], STDOUT_FILENO) == -1) {
        perror ("dup2/se_fd[PIPE_WRITE]");
        _exit (EXIT_FAILURE);
      }
    }
    if (dup2 (se_fd[PIPE_WRITE], STDERR_FILENO) == -1) {
      perror ("dup2/se_fd[PIPE_WRITE]");
      _exit (EXIT_FAILURE);
    }
    close (so_fd[PIPE_WRITE]);
    close (se_fd[PIPE_WRITE]);

    if (flags & COMMAND_FLAG_DO_CHROOT && sysroot_len > 0) {
      if (chroot (sysroot) == -1) {
        perror ("chroot in sysroot");
        _exit (EXIT_FAILURE);
      }
    }

    if (chdir ("/") == -1) {
      perror ("chdir");
      _exit (EXIT_FAILURE);
    }

    execvp (argv[0], (void *) argv);
    perror (argv[0]);
    _exit (EXIT_FAILURE);
  }

  /* Parent process. */
  close (so_fd[PIPE_WRITE]);
  close (se_fd[PIPE_WRITE]);

  FD_ZERO (&rset);
  FD_SET (so_fd[PIPE_READ], &rset);
  FD_SET (se_fd[PIPE_READ], &rset);

  quit = 0;
  while (quit < 2) {
  again:
    rset2 = rset;
    r = select (MAX (so_fd[PIPE_READ], se_fd[PIPE_READ]) + 1, &rset2,
                NULL, NULL, NULL);
    if (r == -1) {
      if (errno == EINTR)
        goto again;

      perror ("select");
    quit:
      if (stdoutput) {
        free (*stdoutput);
        *stdoutput = NULL;
      }
      if (stderror) {
        free (*stderror);
        /* Need to return non-NULL *stderror here since most callers
         * will try to print and then free the err string.
         * Unfortunately recovery from strdup failure here is not
         * possible.
         */
        *stderror = strdup ("error running external command, "
                            "see debug output for details");
      }
      close (so_fd[PIPE_READ]);
      close (se_fd[PIPE_READ]);
      if (flag_copy_stdin) close (flag_copy_fd);
      waitpid (pid, NULL, 0);
      return -1;
    }

    if (FD_ISSET (so_fd[PIPE_READ], &rset2)) { /* something on stdout */
      r = read (so_fd[PIPE_READ], buf, sizeof buf);
      if (r == -1) {
        perror ("read");
        goto quit;
      }
      if (r == 0) { FD_CLR (so_fd[PIPE_READ], &rset); quit++; }

      if (r > 0 && stdoutput) {
        so_size += r;
        p = realloc (*stdoutput, so_size);
        if (p == NULL) {
          perror ("realloc");
          goto quit;
        }
        *stdoutput = p;
        memcpy (*stdoutput + so_size - r, buf, r);
      }
    }

    if (FD_ISSET (se_fd[PIPE_READ], &rset2)) { /* something on stderr */
      r = read (se_fd[PIPE_READ], buf, sizeof buf);
      if (r == -1) {
        perror ("read");
        goto quit;
      }
      if (r == 0) { FD_CLR (se_fd[PIPE_READ], &rset); quit++; }

      if (r > 0) {
        if (verbose)
          ignore_value (write (STDERR_FILENO, buf, r));

        if (stderror) {
          se_size += r;
          p = realloc (*stderror, se_size);
          if (p == NULL) {
            perror ("realloc");
            goto quit;
          }
          *stderror = p;
          memcpy (*stderror + se_size - r, buf, r);
        }
      }
    }
  }

  close (so_fd[PIPE_READ]);
  close (se_fd[PIPE_READ]);

  /* Make sure the output buffers are \0-terminated.  Also remove any
   * trailing \n characters from the error buffer (not from stdout).
   */
  if (stdoutput) {
    void *q = realloc (*stdoutput, so_size+1);
    if (q == NULL) {
      perror ("realloc");
      free (*stdoutput);
    }
    *stdoutput = q;
    if (*stdoutput)
      (*stdoutput)[so_size] = '\0';
  }
  if (stderror) {
    void *q = realloc (*stderror, se_size+1);
    if (q == NULL) {
      perror ("realloc");
      free (*stderror);
    }
    *stderror = q;
    if (*stderror) {
      (*stderror)[se_size] = '\0';
      while (se_size > 0 && (*stderror)[se_size-1] == '\n') {
        se_size--;
        (*stderror)[se_size] = '\0';
      }
    }
  }

  if (flag_copy_stdin && close (flag_copy_fd) == -1) {
    perror ("close");
    return -1;
  }

  /* Get the exit status of the command. */
  if (waitpid (pid, &r, 0) != pid) {
    perror ("waitpid");
    return -1;
  }

  if (WIFEXITED (r)) {
    return WEXITSTATUS (r);
  } else
    return -1;
}
