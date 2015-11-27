/* virt-builder
 * Copyright (C) 2013 Red Hat Inc.
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
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>

#include <pthread.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include "guestfs.h"
#include "guestfs-internal-frontend.h"

#include "ignore-value.h"

#if HAVE_LIBLZMA
#include <lzma.h>
#endif

#ifdef HAVE_CAML_UNIXSUPPORT_H
#include <caml/unixsupport.h>
#else
#define Nothing ((value) 0)
extern void unix_error (int errcode, char * cmdname, value arg) Noreturn;
#endif

#if defined (HAVE_LIBLZMA) && \
  defined (HAVE_LZMA_INDEX_STREAM_FLAGS) && \
  defined (HAVE_LZMA_INDEX_STREAM_PADDING)
#define PARALLEL_XZCAT 1
#else
#define PARALLEL_XZCAT 0
#endif

extern value virt_builder_using_parallel_xzcat (value unitv);

value
virt_builder_using_parallel_xzcat (value unitv)
{
  return PARALLEL_XZCAT ? Val_true : Val_false;
}

#if PARALLEL_XZCAT
static void pxzcat (value filenamev, value outputfilev, unsigned nr_threads);
#endif /* PARALLEL_XZCAT */

extern value virt_builder_pxzcat (value inputfilev, value outputfilev);

value
virt_builder_pxzcat (value inputfilev, value outputfilev)
{
  CAMLparam2 (inputfilev, outputfilev);

#if PARALLEL_XZCAT

  /* Parallel implementation of xzcat (pxzcat). */
  /* XXX Make number of threads configurable? */
  long i;
  unsigned nr_threads;

  i = sysconf (_SC_NPROCESSORS_ONLN);
  if (i <= 0) {
    perror ("could not get number of cores");
    i = 1;
  }
  nr_threads = (unsigned) i;

  /* NB: This might throw an exception if something fails.  If it
   * does, this function won't return as a regular C function.
   */
  pxzcat (inputfilev, outputfilev, nr_threads);

#else /* !PARALLEL_XZCAT */

  /* Fallback: use regular xzcat. */
  int fd;
  pid_t pid;
  int status;

  fd = open (String_val (outputfilev), O_WRONLY|O_CREAT|O_TRUNC|O_NOCTTY, 0666);
  if (fd == -1)
    unix_error (errno, (char *) "open", outputfilev);

  pid = fork ();
  if (pid == -1) {
    int err = errno;
    close (fd);
    unix_error (err, (char *) "fork", Nothing);
  }

  if (pid == 0) {               /* child - run xzcat */
    dup2 (fd, 1);
    execlp (XZCAT, XZCAT, String_val (inputfilev), NULL);
    perror (XZCAT);
    _exit (EXIT_FAILURE);
  }

  close (fd);

  if (waitpid (pid, &status, 0) == -1)
    unix_error (errno, (char *) "waitpid", Nothing);
  if (!WIFEXITED (status) || WEXITSTATUS (status) != 0)
    caml_failwith (XZCAT " program failed, see earlier error messages");

#endif /* !PARALLEL_XZCAT */

  CAMLreturn (Val_unit);
}

#if PARALLEL_XZCAT

#define DEBUG 0

#if DEBUG
#define debug(fs,...) fprintf (stderr, "pxzcat: debug: " fs "\n", ## __VA_ARGS__)
#else
#define debug(fs,...) /* nothing */
#endif

/* Size of buffers used in decompression loop. */
#define BUFFER_SIZE (64*1024)

#define XZ_HEADER_MAGIC     "\xfd" "7zXZ\0"
#define XZ_HEADER_MAGIC_LEN 6

static int check_header_magic (int fd);
static lzma_index *parse_indexes (value filenamev, int fd);
static void iter_blocks (lzma_index *idx, unsigned nr_threads, value filenamev, int fd, value outputfilev, int ofd);

static void
pxzcat (value filenamev, value outputfilev, unsigned nr_threads)
{
  int fd, ofd;
  uint64_t size;
  lzma_index *idx;

  /* Open the file. */
  fd = open (String_val (filenamev), O_RDONLY);
  if (fd == -1)
    unix_error (errno, (char *) "open", filenamev);

  /* Check file magic. */
  if (!check_header_magic (fd)) {
    close (fd);
    caml_invalid_argument ("input file is not an xz file");
  }

  /* Read and parse the indexes. */
  idx = parse_indexes (filenamev, fd);

  /* Get the file uncompressed size, create the output file. */
  size = lzma_index_uncompressed_size (idx);
  debug ("uncompressed size = %" PRIu64 " bytes", size);

  /* Avoid annoying ext4 auto_da_alloc which causes a flush on close
   * unless we are very careful about not truncating a regular file
   * from non-zero size to zero size.  (Thanks Eric Sandeen)
   */
  ofd = open (String_val (outputfilev), O_WRONLY|O_CREAT|O_NOCTTY, 0644);
  if (ofd == -1) {
    int err = errno;
    close (fd);
    unix_error (err, (char *) "open", outputfilev);
  }

  if (ftruncate (ofd, 1) == -1) {
    int err = errno;
    close (fd);
    unix_error (err, (char *) "ftruncate", outputfilev);
  }

  if (lseek (ofd, 0, SEEK_SET) == -1) {
    int err = errno;
    close (fd);
    unix_error (err, (char *) "lseek", outputfilev);
  }

  if (write (ofd, "\0", 1) == -1) {
    int err = errno;
    close (fd);
    unix_error (err, (char *) "write", outputfilev);
  }

  if (ftruncate (ofd, size) == -1) {
    int err = errno;
    close (fd);
    unix_error (err, (char *) "ftruncate", outputfilev);
  }

#if defined HAVE_POSIX_FADVISE
  /* Tell the kernel we won't read the output file. */
  ignore_value (posix_fadvise (fd, 0, 0, POSIX_FADV_RANDOM|POSIX_FADV_DONTNEED));
#endif

  /* Iterate over blocks. */
  iter_blocks (idx, nr_threads, filenamev, fd, outputfilev, ofd);

  lzma_index_end (idx, NULL);

  if (close (fd) == -1)
    unix_error (errno, (char *) "close", filenamev);
}

static int
check_header_magic (int fd)
{
  char buf[XZ_HEADER_MAGIC_LEN];

  if (lseek (fd, 0, SEEK_SET) == -1)
    return 0;
  if (read (fd, buf, XZ_HEADER_MAGIC_LEN) != XZ_HEADER_MAGIC_LEN)
    return 0;
  if (memcmp (buf, XZ_HEADER_MAGIC, XZ_HEADER_MAGIC_LEN) != 0)
    return 0;
  return 1;
}

/* For explanation of this function, see src/xz/list.c:parse_indexes
 * in the xz sources.
 */
static lzma_index *
parse_indexes (value filenamev, int fd)
{
  lzma_ret r;
  off_t pos, index_size;
  uint8_t footer[LZMA_STREAM_HEADER_SIZE];
  uint8_t header[LZMA_STREAM_HEADER_SIZE];
  lzma_stream_flags footer_flags;
  lzma_stream_flags header_flags;
  lzma_stream strm = LZMA_STREAM_INIT;
  ssize_t n;
  lzma_index *combined_index = NULL;
  lzma_index *this_index = NULL;
  lzma_vli stream_padding = 0;
  size_t nr_streams = 0;

  /* Check file size is a multiple of 4 bytes. */
  pos = lseek (fd, 0, SEEK_END);
  if (pos == (off_t) -1)
    unix_error (errno, (char *) "lseek", filenamev);

  if ((pos & 3) != 0)
    caml_invalid_argument ("input not an xz file: size is not a multiple of 4 bytes");

  /* Jump backwards through the file identifying each stream. */
  while (pos > 0) {
    debug ("looping through streams: pos = %" PRIu64, (uint64_t) pos);

    if (pos < LZMA_STREAM_HEADER_SIZE)
      caml_invalid_argument ("corrupted xz file");

    if (lseek (fd, -LZMA_STREAM_HEADER_SIZE, SEEK_CUR) == -1)
      unix_error (errno, (char *) "lseek", filenamev);

    if (read (fd, footer, LZMA_STREAM_HEADER_SIZE) != LZMA_STREAM_HEADER_SIZE)
      unix_error (errno, (char *) "read", filenamev);

    /* Skip stream padding. */
    if (footer[8] == 0 && footer[9] == 0 &&
        footer[10] == 0 && footer[11] == 0) {
      stream_padding += 4;
      pos -= 4;
      continue;
    }

    pos -= LZMA_STREAM_HEADER_SIZE;
    nr_streams++;

    debug ("decode stream footer at pos = %" PRIu64, (uint64_t) pos);

    /* Does the stream footer look reasonable? */
    r = lzma_stream_footer_decode (&footer_flags, footer);
    if (r != LZMA_OK) {
      fprintf (stderr, "invalid stream footer - error %u\n", r);
      caml_invalid_argument ("invalid stream footer");
    }

    debug ("backward_size = %" PRIu64, (uint64_t) footer_flags.backward_size);
    index_size = footer_flags.backward_size;
    if (pos < index_size + LZMA_STREAM_HEADER_SIZE)
      caml_invalid_argument ("invalid stream footer");

    pos -= index_size;
    debug ("decode index at pos = %" PRIu64, (uint64_t) pos);

    /* Seek backwards to the index of this stream. */
    if (lseek (fd, pos, SEEK_SET) == -1)
      unix_error (errno, (char *) "lseek", filenamev);

    /* Decode the index. */
    r = lzma_index_decoder (&strm, &this_index, UINT64_MAX);
    if (r != LZMA_OK) {
      fprintf (stderr, "invalid stream index - error %u\n", r);
      caml_invalid_argument ("invalid stream index");
    }

    do {
      uint8_t buf[BUFSIZ];

      strm.avail_in = index_size;
      if (strm.avail_in > BUFSIZ)
        strm.avail_in = BUFSIZ;

      n = read (fd, &buf, strm.avail_in);
      if (n == -1)
        unix_error (errno, (char *) "read", filenamev);

      index_size -= strm.avail_in;

      strm.next_in = buf;
      r = lzma_code (&strm, LZMA_RUN);
    } while (r == LZMA_OK);

    if (r != LZMA_STREAM_END) {
      fprintf (stderr, "could not parse index - error %u\n", r);
      caml_invalid_argument ("could not parse index");
    }

    pos -= lzma_index_total_size (this_index) + LZMA_STREAM_HEADER_SIZE;

    debug ("decode stream header at pos = %" PRIu64, (uint64_t) pos);

    /* Read and decode the stream header. */
    if (lseek (fd, pos, SEEK_SET) == -1)
      unix_error (errno, (char *) "lseek", filenamev);

    if (read (fd, header, LZMA_STREAM_HEADER_SIZE) != LZMA_STREAM_HEADER_SIZE)
      unix_error (errno, (char *) "read stream header", filenamev);

    r = lzma_stream_header_decode (&header_flags, header);
    if (r != LZMA_OK) {
      fprintf (stderr, "invalid stream header - error %u\n", r);
      caml_invalid_argument ("invalid stream header");
    }

    /* Header and footer of the stream should be equal. */
    r = lzma_stream_flags_compare (&header_flags, &footer_flags);
    if (r != LZMA_OK) {
      fprintf (stderr, "header and footer of stream are not equal - error %u\n",
               r);
      caml_invalid_argument ("header and footer of stream are not equal");
    }

    /* Store the decoded stream flags in this_index. */
    r = lzma_index_stream_flags (this_index, &footer_flags);
    if (r != LZMA_OK) {
      fprintf (stderr, "cannot read stream_flags from index - error %u\n", r);
      caml_invalid_argument ("cannot read stream_flags from index");
    }

    /* Store the amount of stream padding so far.  Needed to calculate
     * compressed offsets correctly in multi-stream files.
     */
    r = lzma_index_stream_padding (this_index, stream_padding);
    if (r != LZMA_OK) {
      fprintf (stderr, "cannot set stream_padding in index - error %u\n", r);
      caml_invalid_argument ("cannot set stream_padding in index");
    }

    if (combined_index != NULL) {
      r = lzma_index_cat (this_index, combined_index, NULL);
      if (r != LZMA_OK) {
        fprintf (stderr, "cannot combine indexes - error %u\n", r);
        caml_invalid_argument ("cannot combine indexes");
      }
    }

    combined_index = this_index;
    this_index = NULL;
  }

  lzma_end (&strm);

  return combined_index;
}

/* Return true iff the buffer is all zero bytes.
 *
 * Note that gcc is smart enough to optimize this properly:
 * http://stackoverflow.com/questions/1493936/faster-means-of-checking-for-an-empty-buffer-in-c/1493989#1493989
 */
static inline int
is_zero (const unsigned char *buffer, size_t size)
{
  size_t i;

  for (i = 0; i < size; ++i) {
    if (buffer[i] != 0)
      return 0;
  }

  return 1;
}

struct global_state {
  /* Current iterator.  Threads update this, but it is protected by a
   * mutex, and each thread takes a copy of it when working on it.
   */
  lzma_index_iter iter;
  lzma_bool iter_finished;
  pthread_mutex_t iter_mutex;

  /* Note that all threads are accessing these fds, so you have
   * to use pread/pwrite instead of lseek!
   */

  /* Input file. */
  const char *filename;
  int fd;

  /* Output file. */
  const char *outputfile;
  int ofd;
};

struct per_thread_state {
  unsigned thread_num;
  struct global_state *global;
  int status;
};

/* Create threads to iterate over the blocks and uncompress. */
static void *worker_thread (void *vp);

static void
iter_blocks (lzma_index *idx, unsigned nr_threads,
             value filenamev, int fd, value outputfilev, int ofd)
{
  struct global_state global;
  struct per_thread_state per_thread[nr_threads];
  pthread_t thread[nr_threads];
  unsigned u, nr_errors;
  int err;
  void *status;

  lzma_index_iter_init (&global.iter, idx);
  global.iter_finished = 0;
  err = pthread_mutex_init (&global.iter_mutex, NULL);
  if (err != 0)
    unix_error (err, (char *) "pthread_mutex_init", Nothing);

  global.filename = String_val (filenamev);
  global.fd = fd;
  global.outputfile = String_val (outputfilev);
  global.ofd = ofd;

  for (u = 0; u < nr_threads; ++u) {
    per_thread[u].thread_num = u;
    per_thread[u].global = &global;
  }

  /* Start the threads. */
  for (u = 0; u < nr_threads; ++u) {
    err = pthread_create (&thread[u], NULL, worker_thread, &per_thread[u]);
    if (err != 0)
      unix_error (err, (char *) "pthread_create", Nothing);
  }

  /* Wait for the threads to exit. */
  nr_errors = 0;
  for (u = 0; u < nr_threads; ++u) {
    err = pthread_join (thread[u], &status);
    if (err != 0) {
      fprintf (stderr, "pthread_join (%u): %s\n", u, strerror (err));
      nr_errors++;
    }
    if (*(int *)status == -1)
      nr_errors++;
  }

  if (nr_errors > 0)
    caml_invalid_argument ("some threads failed, see earlier errors");
}

static int
xpwrite (int fd, const void *bufvp, size_t count, off_t offset)
{
  const char *buf = bufvp;
  ssize_t r;

  while (count > 0) {
    r = pwrite (fd, buf, count, offset);
    if (r == -1)
      return -1;
    count -= r;
    offset += r;
    buf += r;
  }

  return 0;
}

/* Iterate over the blocks and uncompress. */
static void *
worker_thread (void *vp)
{
  struct per_thread_state *state = vp;
  struct global_state *global = state->global;
  lzma_index_iter iter;
  int err;
  off_t position, oposition;
  CLEANUP_FREE uint8_t *header = NULL;
  ssize_t n;
  lzma_block block;
  CLEANUP_FREE lzma_filter *filters = NULL;
  lzma_ret r;
  lzma_stream strm = LZMA_STREAM_INIT;
  CLEANUP_FREE uint8_t *buf = NULL;
  CLEANUP_FREE uint8_t *outbuf = NULL;
  size_t i;
  lzma_bool iter_finished;

  state->status = -1;

  header = malloc (sizeof (uint8_t) * LZMA_BLOCK_HEADER_SIZE_MAX);
  filters = malloc (sizeof (lzma_filter) * (LZMA_FILTERS_MAX + 1));
  buf = malloc (sizeof (uint8_t) * BUFFER_SIZE);
  outbuf = malloc (sizeof (uint8_t) * BUFFER_SIZE);

  if (header == NULL || filters == NULL || buf == NULL || outbuf == NULL) {
    perror ("malloc");
    return &state->status;
  }

  for (;;) {
    /* Get the next block. */
    err = pthread_mutex_lock (&global->iter_mutex);
    if (err != 0) abort ();
    iter_finished = global->iter_finished;
    if (!iter_finished) {
      iter_finished = global->iter_finished =
        lzma_index_iter_next (&global->iter, LZMA_INDEX_ITER_NONEMPTY_BLOCK);
      if (!iter_finished)
        /* Take a local copy of this iterator since another thread will
         * update the global version.
         */
        iter = global->iter;
    }
    err = pthread_mutex_unlock (&global->iter_mutex);
    if (err != 0) abort ();
    if (iter_finished)
      break;

    /* Read the block header.  Start by reading a single byte which
     * tell us how big the block header is.
     */
    position = iter.block.compressed_file_offset;
    n = pread (global->fd, header, 1, position);
    if (n == 0) {
      fprintf (stderr,
               "%s: read: unexpected end of file reading block header byte\n",
               global->filename);
      return &state->status;
    }
    if (n == -1) {
      perror (String_val (global->filename));
      return &state->status;
    }
    position++;

    if (header[0] == '\0') {
      fprintf (stderr,
               "%s: read: unexpected invalid block in file, header[0] = 0\n",
               global->filename);
      return &state->status;
    }

    block.version = 0;
    block.check = iter.stream.flags->check;
    block.filters = filters;
    block.header_size = lzma_block_header_size_decode (header[0]);

    /* Now read and decode the block header. */
    n = pread (global->fd, &header[1], block.header_size-1, position);
    if (n >= 0 && n != (ssize_t) block.header_size-1) {
      fprintf (stderr,
               "%s: read: unexpected end of file reading block header\n",
               global->filename);
      return &state->status;
    }
    if (n == -1) {
      perror (global->filename);
      return &state->status;
    }
    position += n;

    r = lzma_block_header_decode (&block, NULL, header);
    if (r != LZMA_OK) {
      fprintf (stderr, "%s: invalid block header (error %u)\n",
               global->filename, r);
      return &state->status;
    }

    /* What this actually does is it checks that the block header
     * matches the index.
     */
    r = lzma_block_compressed_size (&block, iter.block.unpadded_size);
    if (r != LZMA_OK) {
      fprintf (stderr,
               "%s: cannot calculate compressed size (error %u)\n",
               global->filename, r);
      return &state->status;
    }

    /* Where we will start writing to. */
    oposition = iter.block.uncompressed_file_offset;

    /* Read the block data and uncompress it. */
    r = lzma_block_decoder (&strm, &block);
    if (r != LZMA_OK) {
      fprintf (stderr, "%s: invalid block (error %u)\n", global->filename, r);
      return &state->status;
    }

    strm.next_in = NULL;
    strm.avail_in = 0;
    strm.next_out = outbuf;
    strm.avail_out = BUFFER_SIZE;

    for (;;) {
      lzma_action action = LZMA_RUN;

      if (strm.avail_in == 0) {
        strm.next_in = buf;
        n = pread (global->fd, buf, BUFFER_SIZE, position);
        if (n == -1) {
          perror (global->filename);
          return &state->status;
        }
        position += n;
        strm.avail_in = n;
        if (n == 0)
          action = LZMA_FINISH;
      }

      r = lzma_code (&strm, action);

      if (strm.avail_out == 0 || r == LZMA_STREAM_END) {
        size_t wsz = BUFFER_SIZE - strm.avail_out;

        /* Don't write if the block is all zero, to preserve output file
         * sparseness.  However we have to update oposition.
         */
        if (!is_zero (outbuf, wsz)) {
          if (xpwrite (global->ofd, outbuf, wsz, oposition) == -1) {
            perror (global->outputfile);
            return &state->status;
          }
        }
        oposition += wsz;

        strm.next_out = outbuf;
        strm.avail_out = BUFFER_SIZE;
      }

      if (r == LZMA_STREAM_END)
        break;
      if (r != LZMA_OK) {
        fprintf (stderr,
                 "%s: could not parse block data (error %u)\n",
                 global->filename, r);
        return &state->status;
      }
    }

    lzma_end (&strm);

    for (i = 0; filters[i].id != LZMA_VLI_UNKNOWN; ++i)
      free (filters[i].options);
  }

  state->status = 0;
  return &state->status;
}

#endif /* PARALLEL_XZCAT */
