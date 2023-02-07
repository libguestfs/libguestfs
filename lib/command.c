/* libguestfs
 * Copyright (C) 2010-2023 Red Hat Inc.
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
 * A wrapper for running external commands, loosely based on libvirt's
 * C<virCommand> interface.
 *
 * In outline to use this interface you must:
 *
 * =over 4
 *
 * =item 1.
 *
 * Create a new command handle:
 *
 *  struct command *cmd;
 *  cmd = guestfs_int_new_command (g);
 *
 * =item 2.
 *
 * I<Either> add arguments:
 *
 *  guestfs_int_cmd_add_arg (cmd, "qemu-img");
 *  guestfs_int_cmd_add_arg (cmd, "info");
 *  guestfs_int_cmd_add_arg (cmd, filename);
 *
 * (B<NB:> You don't need to add a C<NULL> argument at the end.)
 *
 * =item 3.
 *
 * I<Or> construct a command using a mix of quoted and unquoted
 * strings.  (This is useful for L<system(3)>/C<popen("r")>-style
 * shell commands, with the added safety of allowing args to be quoted
 * properly).
 *
 *  guestfs_int_cmd_add_string_unquoted (cmd, "qemu-img info ");
 *  guestfs_int_cmd_add_string_quoted (cmd, filename);
 *
 * =item 4.
 *
 * Set various flags, such as whether you want to capture
 * errors in the regular libguestfs error log.
 *
 * =item 5.
 *
 * Run the command.  This is what does the L<fork(2)> call, optionally
 * loops over the output, and then does a L<waitpid(3)> and returns the
 * exit status of the command.
 *
 *  r = guestfs_int_cmd_run (cmd);
 *  if (r == -1)
 *    // error
 *  // else test r using the WIF* functions
 *
 * =item 6.
 *
 * Close the handle:
 *
 *  guestfs_int_cmd_close (cmd);
 *
 * (or use C<CLEANUP_CMD_CLOSE>).
 *
 * =back
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/select.h>

#ifdef HAVE_SYS_TIME_H
#include <sys/time.h>
#endif
#ifdef HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif

#include "guestfs.h"
#include "guestfs-internal.h"

enum command_style {
  COMMAND_STYLE_NOT_SELECTED = 0,
  COMMAND_STYLE_EXECV = 1,
  COMMAND_STYLE_SYSTEM = 2
};

struct command;

static void add_line_buffer (struct command *cmd, const char *buf, size_t len);
static void close_line_buffer (struct command *cmd);
static void add_unbuffered (struct command *cmd, const char *buf, size_t len);
static void add_whole_buffer (struct command *cmd, const char *buf, size_t len);
static void close_whole_buffer (struct command *cmd);

struct buffering {
  char *buffer;
  size_t len;
  void (*add_data) (struct command *cmd, const char *buf, size_t len);
  void (*close_data) (struct command *cmd);
};

struct child_rlimits {
  struct child_rlimits *next;
  int resource;
  long limit;
};

struct command
{
  guestfs_h *g;

  enum command_style style;
  union {
    /* COMMAND_STYLE_EXECV */
    struct stringsbuf argv;
    /* COMMAND_STYLE_SYSTEM */
    struct {
      char *str;
      size_t len, alloc;
    } string;
  };

  /* Capture errors to the error log (defaults to true). */
  bool capture_errors;
  int errorfd;

  /* When using the pipe_* APIs, stderr is pointed to a temporary file. */
  char *error_file;

  /* Close file descriptors (defaults to true). */
  bool close_files;

  /* Supply a callback to receive stdout. */
  cmd_stdout_callback stdout_callback;
  void *stdout_data;
  int outfd;
  struct buffering outbuf;

  /* For programs that send output to stderr.  Hello qemu. */
  bool stderr_to_stdout;

  /* PID of subprocess (if > 0). */
  pid_t pid;

  /* Optional child setup callback. */
  cmd_child_callback child_callback;
  void *child_callback_data;

  /* Optional child limits. */
  struct child_rlimits *child_rlimits;
};

/**
 * Create a new command handle.
 */
struct command *
guestfs_int_new_command (guestfs_h *g)
{
  struct command *cmd;

  cmd = safe_calloc (g, 1, sizeof *cmd);
  cmd->g = g;
  cmd->capture_errors = true;
  cmd->close_files = true;
  cmd->errorfd = -1;
  cmd->outfd = -1;
  return cmd;
}

static void
add_arg_no_strdup (struct command *cmd, char *arg)
{
  assert (cmd->style != COMMAND_STYLE_SYSTEM);
  cmd->style = COMMAND_STYLE_EXECV;

  guestfs_int_add_string_nodup (cmd->g, &cmd->argv, arg);
}

static void
add_arg (struct command *cmd, const char *arg)
{
  assert (arg != NULL);
  add_arg_no_strdup (cmd, safe_strdup (cmd->g, arg));
}

/**
 * Add single arg (for C<execv>-style command execution).
 */
void
guestfs_int_cmd_add_arg (struct command *cmd, const char *arg)
{
  add_arg (cmd, arg);
}

/**
 * Add single arg (for C<execv>-style command execution)
 * using a L<printf(3)>-style format string.
 */
void
guestfs_int_cmd_add_arg_format (struct command *cmd, const char *fs, ...)
{
  va_list args;
  char *arg;
  int err;

  va_start (args, fs);
  err = vasprintf (&arg, fs, args);
  va_end (args);

  if (err < 0)
    cmd->g->abort_cb ();

  add_arg_no_strdup (cmd, arg);
}

static void
add_string (struct command *cmd, const char *str, size_t len)
{
  assert (cmd->style != COMMAND_STYLE_EXECV);
  cmd->style = COMMAND_STYLE_SYSTEM;

  if (cmd->string.len >= cmd->string.alloc) {
    if (cmd->string.alloc == 0)
      cmd->string.alloc = 256;
    else
      cmd->string.alloc += MAX (cmd->string.alloc, len);
    cmd->string.str = safe_realloc (cmd->g, cmd->string.str, cmd->string.alloc);
  }

  memcpy (&cmd->string.str[cmd->string.len], str, len);
  cmd->string.len += len;
}

/**
 * Add a string (for L<system(3)>-style command execution).
 *
 * This variant adds the strings without quoting them, which is
 * dangerous if the string contains untrusted content.
 */
void
guestfs_int_cmd_add_string_unquoted (struct command *cmd, const char *str)
{
  add_string (cmd, str, strlen (str));
}

/**
 * Add a string (for L<system(3)>-style command execution).
 *
 * The string is enclosed in double quotes, with any special
 * characters within the string which need escaping done.  This is
 * used to add a single argument to a L<system(3)>-style command
 * string.
 */
void
guestfs_int_cmd_add_string_quoted (struct command *cmd, const char *str)
{
  add_string (cmd, "\"", 1);

  for (; *str; str++) {
    if (*str == '$' ||
        *str == '`' ||
        *str == '\\' ||
        *str == '"')
      add_string (cmd, "\\", 1);
    add_string (cmd, str, 1);
  }

  add_string (cmd, "\"", 1);
}

/**
 * Set a callback which will capture stdout.
 *
 * If flags contains C<CMD_STDOUT_FLAG_LINE_BUFFER> (the default),
 * then the callback is called line by line on the output.  If there
 * is a trailing C<\n> then it is automatically removed before the
 * callback is called.  The line buffer is C<\0>-terminated.
 *
 * If flags contains C<CMD_STDOUT_FLAG_UNBUFFERED>, then buffers are
 * passed to the callback as it is received from the command.  Note in
 * this case the buffer is I<not> C<\0>-terminated, so you need to may
 * attention to the length field in the callback.
 *
 * If flags contains C<CMD_STDOUT_FLAG_WHOLE_BUFFER>, then the
 * callback is called exactly once, with the entire buffer.  Note in
 * this case the buffer is I<not> C<\0>-terminated, so you need to may
 * attention to the length field in the callback.
 */
void
guestfs_int_cmd_set_stdout_callback (struct command *cmd,
                                     cmd_stdout_callback stdout_callback,
                                     void *stdout_data, unsigned flags)
{
  cmd->stdout_callback = stdout_callback;
  cmd->stdout_data = stdout_data;

  /* Buffering mode. */
  if ((flags & 3) == CMD_STDOUT_FLAG_LINE_BUFFER) {
    cmd->outbuf.add_data = add_line_buffer;
    cmd->outbuf.close_data = close_line_buffer;
  }
  else if ((flags & 3) == CMD_STDOUT_FLAG_UNBUFFERED) {
    cmd->outbuf.add_data = add_unbuffered;
    cmd->outbuf.close_data = NULL;
  }
  else if ((flags & 3) == CMD_STDOUT_FLAG_WHOLE_BUFFER) {
    cmd->outbuf.add_data = add_whole_buffer;
    cmd->outbuf.close_data = close_whole_buffer;
  }
  else
    abort ();
}

/**
 * Equivalent to adding C<2E<gt>&1> to the end of the command.  This
 * is incompatible with the C<capture_errors> flag, because it doesn't
 * make sense to combine them.
 */
void
guestfs_int_cmd_set_stderr_to_stdout (struct command *cmd)
{
  cmd->stderr_to_stdout = true;
}

/**
 * Clear the C<capture_errors> flag.  This means that any errors will
 * go to stderr, instead of being captured in the event log, and that
 * is usually undesirable.
 */
void
guestfs_int_cmd_clear_capture_errors (struct command *cmd)
{
  cmd->capture_errors = false;
}

/**
 * Don't close file descriptors after the fork.
 *
 * XXX Should allow single fds to be sent to child process.
 */
void
guestfs_int_cmd_clear_close_files (struct command *cmd)
{
  cmd->close_files = false;
}

/**
 * Set a function to be executed in the child, right before the
 * execution.  Can be used to setup the child, for example changing
 * its current directory.
 */
void
guestfs_int_cmd_set_child_callback (struct command *cmd,
                                    cmd_child_callback child_callback,
                                    void *data)
{
  cmd->child_callback = child_callback;
  cmd->child_callback_data = data;
}

/**
 * Set up child rlimits, in case the process we are running could
 * consume lots of space or time.
 */
void
guestfs_int_cmd_set_child_rlimit (struct command *cmd, int resource, long limit)
{
  struct child_rlimits *p;

  p = safe_malloc (cmd->g, sizeof *p);
  p->resource = resource;
  p->limit = limit;
  p->next = cmd->child_rlimits;
  cmd->child_rlimits = p;
}


/**
 * Finish off the command by either C<NULL>-terminating the argv array
 * or adding a terminating C<\0> to the string, or die with an
 * internal error if no command has been added.
 */
static void
finish_command (struct command *cmd)
{
  switch (cmd->style) {
  case COMMAND_STYLE_EXECV:
    guestfs_int_end_stringsbuf (cmd->g, &cmd->argv);
    break;

  case COMMAND_STYLE_SYSTEM:
    add_string (cmd, "\0", 1);
    break;

  case COMMAND_STYLE_NOT_SELECTED:
    abort ();
  }
}

static void
debug_command (struct command *cmd)
{
  size_t i, last;

  switch (cmd->style) {
  case COMMAND_STYLE_EXECV:
    debug (cmd->g, "command: run: %s", cmd->argv.argv[0]);
    last = cmd->argv.size-1;     /* omit final NULL pointer */
    for (i = 1; i < last; ++i) {
      if (i < last-1 &&
          cmd->argv.argv[i][0] == '-' && cmd->argv.argv[i+1][0] != '-') {
        debug (cmd->g, "command: run: \\ %s %s",
               cmd->argv.argv[i], cmd->argv.argv[i+1]);
        i++;
      }
      else
        debug (cmd->g, "command: run: \\ %s", cmd->argv.argv[i]);
    }
    break;

  case COMMAND_STYLE_SYSTEM:
    debug (cmd->g, "command: run: %s", cmd->string.str);
    break;

  case COMMAND_STYLE_NOT_SELECTED:
    abort ();
  }
}

static void run_child (struct command *cmd,
                       char **env) __attribute__((noreturn));

static int
run_command (struct command *cmd)
{
  int errorfd[2] = { -1, -1 };
  int outfd[2] = { -1, -1 };
  CLEANUP_FREE_STRING_LIST char **env = NULL;

  /* Set up a pipe to capture command output and send it to the error log. */
  if (cmd->capture_errors) {
    if (pipe2 (errorfd, O_CLOEXEC) == -1) {
      perrorf (cmd->g, "pipe2");
      goto error;
    }
  }

  /* Set up a pipe to capture stdout for the callback. */
  if (cmd->stdout_callback) {
    if (pipe2 (outfd, O_CLOEXEC) == -1) {
      perrorf (cmd->g, "pipe2");
      goto error;
    }
  }

  env = guestfs_int_copy_environ (environ, "LC_ALL", "C", NULL);
  if (env == NULL)
    goto error;

  cmd->pid = fork ();
  if (cmd->pid == -1) {
    perrorf (cmd->g, "fork");
    goto error;
  }

  /* In parent, return to caller. */
  if (cmd->pid > 0) {
    if (cmd->capture_errors) {
      close (errorfd[1]);
      errorfd[1] = -1;
      cmd->errorfd = errorfd[0];
      errorfd[0] = -1;
    }

    if (cmd->stdout_callback) {
      close (outfd[1]);
      outfd[1] = -1;
      cmd->outfd = outfd[0];
      outfd[0] = -1;
    }

    return 0;
  }

  /* Child process. */
  if (cmd->capture_errors) {
    close (errorfd[0]);
    if (!cmd->stdout_callback)
      dup2 (errorfd[1], 1);
    dup2 (errorfd[1], 2);
    close (errorfd[1]);
  }

  if (cmd->stdout_callback) {
    close (outfd[0]);
    dup2 (outfd[1], 1);
    close (outfd[1]);
  }

  if (cmd->stderr_to_stdout)
    dup2 (1, 2);

  run_child (cmd, env);
  /*NOTREACHED*/

 error:
  if (errorfd[0] >= 0)
    close (errorfd[0]);
  if (errorfd[1] >= 0)
    close (errorfd[1]);
  if (outfd[0] >= 0)
    close (outfd[0]);
  if (outfd[1] >= 0)
    close (outfd[1]);

  return -1;
}

static void
run_child (struct command *cmd, char **env)
{
  struct sigaction sa;
  int i, err, fd, max_fd, r;
  char status_string[80];
#ifdef HAVE_SETRLIMIT
  struct child_rlimits *child_rlimit;
  struct rlimit rlimit;
#endif

  /* Remove all signal handlers.  See the justification here:
   * https://www.redhat.com/archives/libvir-list/2008-August/msg00303.html
   * We don't mask signal handlers yet, so this isn't completely
   * race-free, but better than not doing it at all.
   */
  memset (&sa, 0, sizeof sa);
  sa.sa_handler = SIG_DFL;
  sa.sa_flags = 0;
  sigemptyset (&sa.sa_mask);
  for (i = 1; i < NSIG; ++i)
    sigaction (i, &sa, NULL);

  if (cmd->close_files) {
    /* Close all other file descriptors.  This ensures that we don't
     * hold open (eg) pipes from the parent process.
     */
    max_fd = sysconf (_SC_OPEN_MAX);
    if (max_fd == -1)
      max_fd = 1024;
    if (max_fd > 65536)
      max_fd = 65536;        /* bound the amount of work we do here */
    for (fd = 3; fd < max_fd; ++fd)
      close (fd);
  }

  /* Set the umask for all subcommands to something sensible (RHBZ#610880). */
  umask (022);

  if (cmd->child_callback) {
    if (cmd->child_callback (cmd->g, cmd->child_callback_data) == -1)
      _exit (EXIT_FAILURE);
  }

#ifdef HAVE_SETRLIMIT
  for (child_rlimit = cmd->child_rlimits;
       child_rlimit != NULL;
       child_rlimit = child_rlimit->next) {
    rlimit.rlim_cur = rlimit.rlim_max = child_rlimit->limit;
    if (setrlimit (child_rlimit->resource, &rlimit) == -1) {
      /* EPERM means we're trying to raise the limit (ie. the limit is
       * already more restrictive than what we want), so ignore it.
       */
      if (errno != EPERM) {
        perror ("setrlimit");
        _exit (EXIT_FAILURE);
      }
    }
  }
#endif /* HAVE_SETRLIMIT */

  /* NB: If the main process (which we have forked a copy of) uses
   * more heap than the RLIMIT_AS we set above, then any call to
   * malloc or any extension of the stack will fail with ENOMEM or
   * SIGSEGV respectively.  Luckily we only use RLIMIT_AS followed by
   * execvp below, so we get away with it, but adding any code here
   * could cause a failure.
   *
   * There is a regression test for this.  See:
   * tests/regressions/test-big-heap.c
   */

  /* Note the assignment of environ avoids using execvpe which is a
   * GNU extension.  See also:
   * https://github.com/libguestfs/libnbd/commit/dc64ac5cdd0bc80ca4e18935ad0e8801d11a8644
   */
  environ = env;

  /* Run the command. */
  switch (cmd->style) {
  case COMMAND_STYLE_EXECV:
    execvp (cmd->argv.argv[0], cmd->argv.argv);
    err = errno;
    perror (cmd->argv.argv[0]);
    /* These error codes are defined in POSIX and meant to be the
     * same as the shell.
     */
    _exit (err == ENOENT ? 127 : 126);

  case COMMAND_STYLE_SYSTEM:
    r = system (cmd->string.str);
    if (r == -1) {
      perror ("system");
      _exit (EXIT_FAILURE);
    }
    if (WIFEXITED (r))
      _exit (WEXITSTATUS (r));
    fprintf (stderr, "%s\n",
             guestfs_int_exit_status_to_string (r, cmd->string.str,
                                                status_string,
                                                sizeof status_string));
    _exit (EXIT_FAILURE);

  case COMMAND_STYLE_NOT_SELECTED:
    abort ();
  }

  /*NOTREACHED*/
  abort ();
}

/**
 * The loop which reads errors and output and directs it either to the
 * log or to the stdout callback as appropriate.
 */
static int
loop (struct command *cmd)
{
  fd_set rset, rset2;
  int maxfd = -1, r;
  size_t nr_fds = 0;
  CLEANUP_FREE char *buf = safe_malloc (cmd->g, BUFSIZ);
  ssize_t n;

  FD_ZERO (&rset);

  if (cmd->errorfd >= 0) {
    FD_SET (cmd->errorfd, &rset);
    maxfd = MAX (cmd->errorfd, maxfd);
    nr_fds++;
  }

  if (cmd->outfd >= 0) {
    FD_SET (cmd->outfd, &rset);
    maxfd = MAX (cmd->outfd, maxfd);
    nr_fds++;
  }

  while (nr_fds > 0) {
    rset2 = rset;
    r = select (maxfd+1, &rset2, NULL, NULL, NULL);
    if (r == -1) {
      if (errno == EINTR || errno == EAGAIN)
        continue;
      perrorf (cmd->g, "select");
      return -1;
    }

    if (cmd->errorfd >= 0 && FD_ISSET (cmd->errorfd, &rset2)) {
      /* Read output and send it to the log. */
      n = read (cmd->errorfd, buf, BUFSIZ);
      if (n > 0)
        guestfs_int_call_callbacks_message (cmd->g, GUESTFS_EVENT_APPLIANCE,
                                            buf, n);
      else if (n == 0) {
        if (close (cmd->errorfd) == -1)
          perrorf (cmd->g, "close: errorfd");
        FD_CLR (cmd->errorfd, &rset);
        cmd->errorfd = -1;
        nr_fds--;
      }
      else if (n == -1) {
        perrorf (cmd->g, "read: errorfd");
        close (cmd->errorfd);
        FD_CLR (cmd->errorfd, &rset);
        cmd->errorfd = -1;
        nr_fds--;
      }
    }

    if (cmd->outfd >= 0 && FD_ISSET (cmd->outfd, &rset2)) {
      /* Read the output, buffer it up to the end of the line, then
       * pass it to the callback.
       */
      n = read (cmd->outfd, buf, BUFSIZ);
      if (n > 0) {
        if (cmd->outbuf.add_data)
          cmd->outbuf.add_data (cmd, buf, n);
      }
      else if (n == 0) {
        if (cmd->outbuf.close_data)
          cmd->outbuf.close_data (cmd);
        if (close (cmd->outfd) == -1)
          perrorf (cmd->g, "close: outfd");
        FD_CLR (cmd->outfd, &rset);
        cmd->outfd = -1;
        nr_fds--;
      }
      else if (n == -1) {
        perrorf (cmd->g, "read: outfd");
        close (cmd->outfd);
        FD_CLR (cmd->outfd, &rset);
        cmd->outfd = -1;
        nr_fds--;
      }
    }
  }

  return 0;
}

static int
wait_command (struct command *cmd)
{
  int status;

  if (guestfs_int_waitpid (cmd->g, cmd->pid, &status, "command") == -1)
    return -1;

  cmd->pid = 0;

  return status;
}

/**
 * Fork, run the command, loop over the output, and waitpid.
 *
 * Returns the exit status.  Test it using C<WIF*> macros.
 *
 * On error: Calls C<error> and returns C<-1>.
 */
int
guestfs_int_cmd_run (struct command *cmd)
{
  finish_command (cmd);

  if (cmd->g->verbose)
    debug_command (cmd);

  if (run_command (cmd) == -1)
    return -1;

  if (loop (cmd) == -1)
    return -1;

  return wait_command (cmd);
}

/**
 * Fork and run the command, but don't wait.  Roughly equivalent to
 * S<C<popen (..., "r"|"w")>>.
 *
 * Returns the file descriptor of the pipe, connected to stdout
 * (C<"r">) or stdin (C<"w">) of the child process.
 *
 * After reading/writing to this pipe, call
 * C<guestfs_int_cmd_pipe_wait> to wait for the status of the child.
 *
 * Errors from the subcommand cannot be captured to the error log
 * using this interface.  Instead the caller should call
 * C<guestfs_int_cmd_get_pipe_errors> (after
 * C<guestfs_int_cmd_pipe_wait> returns an error).
 */
int
guestfs_int_cmd_pipe_run (struct command *cmd, const char *mode)
{
  int fd[2] = { -1, -1 };
  int errfd = -1;
  int r_mode;
  int ret;
  CLEANUP_FREE_STRING_LIST char **env = NULL;

  finish_command (cmd);

  if (cmd->g->verbose)
    debug_command (cmd);

  /* Various options cannot be used here. */
  assert (!cmd->capture_errors);
  assert (!cmd->stdout_callback);
  assert (!cmd->stderr_to_stdout);

  if (STREQ (mode, "r"))      r_mode = 1;
  else if (STREQ (mode, "w")) r_mode = 0;
  else abort ();

  if (pipe2 (fd, O_CLOEXEC) == -1) {
    perrorf (cmd->g, "pipe2");
    goto error;
  }

  /* We can't easily capture errors from the child process, so instead
   * we write them into a temporary file and provide a separate
   * function for the caller to read the error messages.
   */
  cmd->error_file = guestfs_int_make_temp_path (cmd->g, "cmderr", "txt");
  if (!cmd->error_file)
    goto error;
  errfd = open (cmd->error_file,
                O_WRONLY|O_CREAT|O_NOCTTY|O_TRUNC|O_CLOEXEC, 0600);
  if (errfd == -1) {
    perrorf (cmd->g, "open: %s", cmd->error_file);
    goto error;
  }

  env = guestfs_int_copy_environ (environ, "LC_ALL", "C", NULL);
  if (env == NULL)
    goto error;

  cmd->pid = fork ();
  if (cmd->pid == -1) {
    perrorf (cmd->g, "fork");
    goto error;
  }

  /* Parent. */
  if (cmd->pid > 0) {
    close (errfd);
    errfd = -1;

    if (r_mode) {
      close (fd[1]);
      ret = fd[0];
    }
    else {
      close (fd[0]);
      ret = fd[1];
    }

    return ret;
  }

  /* Child. */
  dup2 (errfd, 2);
  close (errfd);

  if (r_mode) {
    close (fd[0]);
    dup2 (fd[1], 1);
    close (fd[1]);
  }
  else {
    close (fd[1]);
    dup2 (fd[0], 0);
    close (fd[0]);
  }

  run_child (cmd, env);
  /*NOTREACHED*/

 error:
  if (errfd >= 0)
    close (errfd);
  if (fd[0] >= 0)
    close (fd[0]);
  if (fd[1] >= 0)
    close (fd[1]);
  return -1;
}

/**
 * Wait for a subprocess created by C<guestfs_int_cmd_pipe_run> to
 * finish.  On error (eg. failed syscall) this returns C<-1> and sets
 * the error.  If the subcommand fails, then use C<WIF*> macros to
 * check this, and call C<guestfs_int_cmd_get_pipe_errors> to read
 * the error messages printed by the child.
 */
int
guestfs_int_cmd_pipe_wait (struct command *cmd)
{
  return wait_command (cmd);
}

/**
 * Read the error messages printed by the child.  The caller must free
 * the returned buffer after use.
 */
char *
guestfs_int_cmd_get_pipe_errors (struct command *cmd)
{
  char *ret;
  size_t len;

  assert (cmd->error_file != NULL);

  if (guestfs_int_read_whole_file (cmd->g, cmd->error_file, &ret, NULL) == -1)
    return NULL;

  /* If the file ends with \n characters, trim them. */
  len = strlen (ret);
  while (len > 0 && ret[len-1] == '\n') {
    ret[len-1] = '\0';
    len--;
  }

  return ret;
}

/**
 * Close the C<cmd> object and free all resources.
 */
void
guestfs_int_cmd_close (struct command *cmd)
{
  struct child_rlimits *child_rlimit, *child_rlimit_next;

  if (!cmd)
    return;

  switch (cmd->style) {
  case COMMAND_STYLE_NOT_SELECTED:
    /* nothing */
    break;

  case COMMAND_STYLE_EXECV:
    guestfs_int_free_stringsbuf (&cmd->argv);
    break;

  case COMMAND_STYLE_SYSTEM:
    free (cmd->string.str);
    break;
  }

  if (cmd->error_file != NULL) {
    unlink (cmd->error_file);
    free (cmd->error_file);
  }

  if (cmd->errorfd >= 0)
    close (cmd->errorfd);

  if (cmd->outfd >= 0)
    close (cmd->outfd);

  free (cmd->outbuf.buffer);

  if (cmd->pid > 0)
    guestfs_int_waitpid_noerror (cmd->pid);

  for (child_rlimit = cmd->child_rlimits; child_rlimit != NULL;
       child_rlimit = child_rlimit_next) {
    child_rlimit_next = child_rlimit->next;
    free (child_rlimit);
  }

  free (cmd);
}

void
guestfs_int_cleanup_cmd_close (struct command **ptr)
{
  guestfs_int_cmd_close (*ptr);
}

/**
 * Deal with buffering stdout for the callback.
 */
static void
process_line_buffer (struct command *cmd, int closed)
{
  guestfs_h *g = cmd->g;
  char *p;
  size_t len, newlen;

  while (cmd->outbuf.len > 0) {
    /* Length of the next line. */
    p = strchr (cmd->outbuf.buffer, '\n');
    if (p != NULL) {            /* Got a whole line. */
      len = p - cmd->outbuf.buffer;
      newlen = cmd->outbuf.len - len - 1;
    }
    else if (closed) {          /* Consume rest of input even if no \n found. */
      len = cmd->outbuf.len;
      newlen = 0;
    }
    else                        /* Need to wait for more input. */
      break;

    /* Call the callback with the next line. */
    cmd->outbuf.buffer[len] = '\0';
    cmd->stdout_callback (g, cmd->stdout_data, cmd->outbuf.buffer, len);

    /* Remove the consumed line from the buffer. */
    cmd->outbuf.len = newlen;
    memmove (cmd->outbuf.buffer, cmd->outbuf.buffer + len + 1, newlen);

    /* Keep the buffer \0 terminated. */
    cmd->outbuf.buffer[newlen] = '\0';
  }
}

static void
add_line_buffer (struct command *cmd, const char *buf, size_t len)
{
  guestfs_h *g = cmd->g;
  size_t oldlen;

  /* Append the new content to the end of the current buffer.  Keep
   * the buffer \0 terminated to make things simple when processing
   * the buffer.
   */
  oldlen = cmd->outbuf.len;
  cmd->outbuf.len += len;
  cmd->outbuf.buffer = safe_realloc (g, cmd->outbuf.buffer,
                                     cmd->outbuf.len + 1 /* for \0 */);
  memcpy (cmd->outbuf.buffer + oldlen, buf, len);
  cmd->outbuf.buffer[cmd->outbuf.len] = '\0';

  process_line_buffer (cmd, 0);
}

static void
close_line_buffer (struct command *cmd)
{
  process_line_buffer (cmd, 1);
}

static void
add_unbuffered (struct command *cmd, const char *buf, size_t len)
{
  cmd->stdout_callback (cmd->g, cmd->stdout_data, buf, len);
}

static void
add_whole_buffer (struct command *cmd, const char *buf, size_t len)
{
  guestfs_h *g = cmd->g;
  size_t oldlen;

  /* Append the new content to the end of the current buffer. */
  oldlen = cmd->outbuf.len;
  cmd->outbuf.len += len;
  cmd->outbuf.buffer = safe_realloc (g, cmd->outbuf.buffer, cmd->outbuf.len);
  memcpy (cmd->outbuf.buffer + oldlen, buf, len);
}

static void
close_whole_buffer (struct command *cmd)
{
  cmd->stdout_callback (cmd->g, cmd->stdout_data,
                        cmd->outbuf.buffer, cmd->outbuf.len);
}
