/* guestfish - the filesystem interactive shell
 * Copyright (C) 2010-2011 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <math.h>
#include <sys/time.h>

#include <guestfs.h>

#include "fish.h"
#include "rmsd.h"

/* Include these last since they redefine symbols such as 'lines'
 * which seriously breaks other headers.
 */
#include <term.h>
#include <curses.h>

/* Provided by termcap or terminfo emulation, but not defined
 * in any header file.
 */
extern const char *UP;

static const char *
spinner (int count)
{
  /* Choice of unicode spinners.
   *
   * For basic dingbats, see:
   * http://www.fileformat.info/info/unicode/block/geometric_shapes/utf8test.htm
   * http://www.fileformat.info/info/unicode/block/dingbats/utf8test.htm
   *
   * Arrows are a mess in unicode.  This page helps a lot:
   * http://xahlee.org/comp/unicode_arrows.html
   *
   * I prefer something which doesn't point, just spins.
   */
  /* Black pointing triangle. */
  //static const char *us[] = { "\u25b2", "\u25b6", "\u25bc", "\u25c0" };
  /* White pointing triangle. */
  //static const char *us[] = { "\u25b3", "\u25b7", "\u25bd", "\u25c1" };
  /* Circle with half black. */
  static const char *us[] = { "\u25d0", "\u25d3", "\u25d1", "\u25d2" };
  /* White square white quadrant. */
  //static const char *us[] = { "\u25f0", "\u25f3", "\u25f2", "\u25f1" };
  /* White circle white quadrant. */
  //static const char *us[] = { "\u25f4", "\u25f7", "\u25f6", "\u25f5" };
  /* Black triangle. */
  //static const char *us[] = { "\u25e2", "\u25e3", "\u25e4", "\u25e5" };
  /* Spinning arrow in 8 directions. */
  //static const char *us[] = { "\u2190", "\u2196", "\u2191", "\u2197",
  //                            "\u2192", "\u2198", "\u2193", "\u2199" };

  /* ASCII spinner. */
  static const char *as[] = { "/", "-", "\\", "|" };

  const char **s;
  size_t n;

  if (utf8_mode) {
    s = us;
    n = sizeof us / sizeof us[0];
  }
  else {
    s = as;
    n = sizeof as / sizeof as[0];
  }

  return s[count % n];
}

static double start;         /* start time of command */
static int count;            /* number of progress notifications per cmd */
static struct rmsd rmsd;     /* running mean and standard deviation */

/* This function is called just before we issue any command. */
void
reset_progress_bar (void)
{
  /* The time at which this command was issued. */
  struct timeval start_t;
  gettimeofday (&start_t, NULL);

  start = start_t.tv_sec + start_t.tv_usec / 1000000.;

  count = 0;

  rmsd_init (&rmsd);
}

/* Return remaining time estimate (in seconds) for current call.
 *
 * This returns the running mean estimate of remaining time, but if
 * the latest estimate of total time is greater than two s.d.'s from
 * the running mean then we don't print anything because we're not
 * confident that the estimate is meaningful.  (Returned value is <0.0
 * when nothing should be printed).
 */
static double
estimate_remaining_time (double ratio)
{
  if (ratio <= 0.)
    return -1.0;

  struct timeval now_t;
  gettimeofday (&now_t, NULL);

  double now = now_t.tv_sec + now_t.tv_usec / 1000000.;
  /* We've done 'ratio' of the work in 'now - start' seconds. */
  double time_passed = now - start;

  double total_time = time_passed / ratio;

  /* Add total_time to running mean and s.d. and then see if our
   * estimate of total time is meaningful.
   */
  rmsd_add_sample (&rmsd, total_time);

  double mean = rmsd_get_mean (&rmsd);
  double sd = rmsd_get_standard_deviation (&rmsd);
  if (fabs (total_time - mean) >= 2.0*sd)
    return -1.0;

  /* Don't return early estimates. */
  if (time_passed < 3.0)
    return -1.0;

  return total_time - time_passed;
}

/* The overhead is how much we subtract before we get to the progress
 * bar itself.
 *
 * / 100% [########---------------] xx:xx
 * | |    |                       | |
 * | |    |                       | time (5 cols)
 * | |    |                       |
 * | |    open paren + close paren + space (3 cols)
 * | |
 * | percentage and space (5 cols)
 * |
 * spinner and space (2 cols)
 *
 * Total = 2 + 5 + 3 + 5 = 15
 */
#define COLS_OVERHEAD 15

/* Callback which displays a progress bar. */
void
progress_callback (guestfs_h *g, void *data,
                   uint64_t event, int event_handle, int flags,
                   const char *buf, size_t buf_len,
                   const uint64_t *array, size_t array_len)
{
  int i, cols;
  double ratio;
  const char *s_open, *s_dot, *s_dash, *s_close;

  if (utf8_mode) {
    s_open = "\u27e6"; s_dot = "\u2589"; s_dash = "\u2550"; s_close = "\u27e7";
  } else {
    s_open = "["; s_dot = "#"; s_dash = "-"; s_close = "]";
  }

  if (array_len < 4)
    return;

  /*uint64_t proc_nr = array[0];*/
  /*uint64_t serial = array[1];*/
  uint64_t position = array[2];
  uint64_t total = array[3];

  if (have_terminfo == 0) {
  dumb:
    printf ("%" PRIu64 "/%" PRIu64 "\n", position, total);
  } else {
    cols = tgetnum ((char *) "co");
    if (cols < 32) goto dumb;

    /* Update an existing progress bar just printed? */
    if (count > 0)
      tputs (UP, 2, putchar);
    count++;

    ratio = (double) position / total;
    if (ratio < 0) ratio = 0; else if (ratio > 1) ratio = 1;

    if (ratio < 1) {
      int percent = 100.0 * ratio;
      printf ("%s%3d%% ", spinner (count), percent);
    }
    else {
      fputs (" 100% ", stdout);
    }

    int dots = ratio * (double) (cols - COLS_OVERHEAD);


    fputs (s_open, stdout);
    int i;
    for (i = 0; i < dots; ++i)
      fputs (s_dot, stdout);
    for (i = dots; i < cols - COLS_OVERHEAD; ++i)
      fputs (s_dash, stdout);
    fputs (s_close, stdout);
    fputc (' ', stdout);

    /* Time estimate. */
    double estimate = estimate_remaining_time (ratio);
    if (estimate >= 100.0 * 60.0 * 60.0 /* >= 100 hours */) {
      /* Display hours<h> */
      estimate /= 60. * 60.;
      int hh = floor (estimate);
      printf (">%dh", hh);
    } else if (estimate >= 100.0 * 60.0 /* >= 100 minutes */) {
      /* Display hours<h>minutes */
      estimate /= 60. * 60.;
      int hh = floor (estimate);
      double ignore;
      int mm = floor (modf (estimate, &ignore) * 60.);
      printf ("%02dh%02d", hh, mm);
    } else if (estimate >= 0.0) {
      /* Display minutes:seconds */
      estimate /= 60.;
      int mm = floor (estimate);
      double ignore;
      int ss = floor (modf (estimate, &ignore) * 60.);
      printf ("%02d:%02d", mm, ss);
    }
    else /* < 0 means estimate was not meaningful */
      fputs ("--:--", stdout);

    fputc ('\n', stdout);
  }
}
