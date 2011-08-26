/* libguestfs - mini library for progress bars.
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
#include <string.h>
#include <inttypes.h>
#include <math.h>
#include <sys/time.h>
#include <langinfo.h>

#include "progress.h"

/* Include these last since they redefine symbols such as 'lines'
 * which seriously breaks other headers.
 */
#include <term.h>
#include <curses.h>

/* Provided by termcap or terminfo emulation, but not defined
 * in any header file.
 */
extern const char *UP;

#define STREQ(a,b) (strcmp((a),(b)) == 0)

/* Compute the running mean and standard deviation from the
 * series of estimated values.
 *
 * Method:
 * http://en.wikipedia.org/wiki/Standard_deviation#Rapid_calculation_methods
 * Checked in a test program against answers given by Wolfram Alpha.
 */
struct rmsd {
  double a;                     /* mean */
  double i;                     /* number of samples */
  double q;
};

static void
rmsd_init (struct rmsd *r)
{
  r->a = 0;
  r->i = 1;
  r->q = 0;
}

static void
rmsd_add_sample (struct rmsd *r, double x)
{
  double a_next, q_next;

  a_next = r->a + (x - r->a) / r->i;
  q_next = r->q + (x - r->a) * (x - a_next);
  r->a = a_next;
  r->q = q_next;
  r->i += 1.0;
}

static double
rmsd_get_mean (const struct rmsd *r)
{
  return r->a;
}

static double
rmsd_get_standard_deviation (const struct rmsd *r)
{
  return sqrt (r->q / (r->i - 1.0));
}

struct progress_bar {
  double start;         /* start time of command */
  int count;            /* number of progress notifications per cmd */
  struct rmsd rmsd;     /* running mean and standard deviation */
  int have_terminfo;
  int utf8_mode;
};

struct progress_bar *
progress_bar_init (unsigned flags)
{
  struct progress_bar *bar;
  char *term;

  bar = malloc (sizeof *bar);
  if (bar == NULL)
    return NULL;

  bar->utf8_mode = STREQ (nl_langinfo (CODESET), "UTF-8");

  bar->have_terminfo = 0;

  term = getenv ("TERM");
  if (term) {
    if (tgetent (NULL, term) == 1)
      bar->have_terminfo = 1;
  }

  /* Call this to ensure the other fields are in a reasonable state.
   * It is still the caller's responsibility to reset the progress bar
   * before each command.
   */
  progress_bar_reset (bar);

  return bar;
}

void
progress_bar_free (struct progress_bar *bar)
{
  free (bar);
}

/* This function is called just before we issue any command. */
void
progress_bar_reset (struct progress_bar *bar)
{
  /* The time at which this command was issued. */
  struct timeval start_t;
  gettimeofday (&start_t, NULL);

  bar->start = start_t.tv_sec + start_t.tv_usec / 1000000.;

  bar->count = 0;

  rmsd_init (&bar->rmsd);
}

static const char *
spinner (struct progress_bar *bar, int count)
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

  if (bar->utf8_mode) {
    s = us;
    n = sizeof us / sizeof us[0];
  }
  else {
    s = as;
    n = sizeof as / sizeof as[0];
  }

  return s[count % n];
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
estimate_remaining_time (struct progress_bar *bar, double ratio)
{
  if (ratio <= 0.)
    return -1.0;

  struct timeval now_t;
  gettimeofday (&now_t, NULL);

  double now = now_t.tv_sec + now_t.tv_usec / 1000000.;
  /* We've done 'ratio' of the work in 'now - start' seconds. */
  double time_passed = now - bar->start;

  double total_time = time_passed / ratio;

  /* Add total_time to running mean and s.d. and then see if our
   * estimate of total time is meaningful.
   */
  rmsd_add_sample (&bar->rmsd, total_time);

  double mean = rmsd_get_mean (&bar->rmsd);
  double sd = rmsd_get_standard_deviation (&bar->rmsd);
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

void
progress_bar_set (struct progress_bar *bar,
                  uint64_t position, uint64_t total)
{
  int i, cols, pulse_mode;
  double ratio;
  const char *s_open, *s_dot, *s_dash, *s_close;

  if (bar->utf8_mode) {
    s_open = "\u27e6"; s_dot = "\u2593"; s_dash = "\u2550"; s_close = "\u27e7";
  } else {
    s_open = "["; s_dot = "#"; s_dash = "-"; s_close = "]";
  }

  if (bar->have_terminfo == 0) {
  dumb:
    printf ("%" PRIu64 "/%" PRIu64 "\n", position, total);
  } else {
    cols = tgetnum ((char *) "co");
    if (cols < 32) goto dumb;

    /* Update an existing progress bar just printed? */
    if (bar->count > 0)
      tputs (UP, 2, putchar);
    bar->count++;

    /* Find out if we're in "pulse mode". */
    pulse_mode = position == 0 && total == 1;

    ratio = (double) position / total;
    if (ratio < 0) ratio = 0; else if (ratio > 1) ratio = 1;

    if (pulse_mode) {
      printf ("%s --- ", spinner (bar, bar->count));
    }
    else if (ratio < 1) {
      int percent = 100.0 * ratio;
      printf ("%s%3d%% ", spinner (bar, bar->count), percent);
    }
    else {
      fputs (" 100% ", stdout);
    }

    fputs (s_open, stdout);

    if (!pulse_mode) {
      int dots = ratio * (double) (cols - COLS_OVERHEAD);

      for (i = 0; i < dots; ++i)
        fputs (s_dot, stdout);
      for (i = dots; i < cols - COLS_OVERHEAD; ++i)
        fputs (s_dash, stdout);
    }
    else {           /* "Pulse mode": the progress bar just pulses. */
      for (i = 0; i < cols - COLS_OVERHEAD; ++i) {
        int cc = (bar->count * 3 - i) % (cols - COLS_OVERHEAD);
        if (cc >= 0 && cc <= 3)
          fputs (s_dot, stdout);
        else
          fputs (s_dash, stdout);
      }
    }

    fputs (s_close, stdout);
    fputc (' ', stdout);

    /* Time estimate. */
    double estimate = estimate_remaining_time (bar, ratio);
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
