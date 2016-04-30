/* libguestfs
 * Copyright (C) 2016 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef GUESTFS_BOOT_ANALYSIS_H_
#define GUESTFS_BOOT_ANALYSIS_H_

#define NR_WARMUP_PASSES 3
#define NR_TEST_PASSES   5

/* Per-pass data collected. */
struct pass_data {
  size_t pass;
  struct timespec start_t;
  struct timespec end_t;
  int64_t elapsed_ns;

  /* Array of timestamped events. */
  size_t nr_events;
  struct event *events;

  /* Was the previous appliance log message incomplete?  If so, this
   * contains the index of that incomplete message in the events
   * array.
   */
  ssize_t incomplete_log_message;

  /* Have we seen the launch event yet?  We don't record events until
   * this one has been received.  This makes it easy to base the
   * timeline at event 0.
   */
  int seen_launch;
};

/* The 'source' field in the event is a guestfs event
 * (GUESTFS_EVENT_*).  We also wish to encode libvirt as a source, so
 * we use a magic/impossible value for that here.  Note that events
 * are bitmasks, and normally no more than one bit may be set.
 */
#define SOURCE_LIBVIRT ((uint64_t)~0)
extern char *source_to_string (uint64_t source);

struct event {
  struct timespec t;
  uint64_t source;
  char *message;
};

extern struct pass_data pass_data[NR_TEST_PASSES];

/* The final timeline consisting of various activities starting and
 * ending.  We're interested in when the activities start, and how
 * long they take (mean, variance, standard deviation of length).
 */
struct activity {
  char *name;                   /* Name of this activity. */
  int flags;
#define LONG_ACTIVITY 1         /* Expected to take a long time. */

  /* For each pass, record the actual start & end events of this
   * activity.
   */
  size_t start_event[NR_TEST_PASSES];
  size_t end_event[NR_TEST_PASSES];

  double t;                     /* Start (ns offset). */
  double end_t;                 /* t + mean - 1 */

  /* Length of this activity. */
  double mean;                  /* Mean time elapsed (ns). */
  double variance;              /* Variance. */
  double sd;                    /* Standard deviation. */
  double percent;               /* Percent of total elapsed time. */

  int warning;                  /* Appears in red. */
};

extern size_t nr_activities;
extern struct activity *activities;

extern int activity_exists (const char *name);
extern struct activity *add_activity (const char *name, int flags);
extern struct activity *find_activity (const char *name);
extern int activity_exists_with_no_data (const char *name, size_t pass);

extern void construct_timeline (void);

#endif /* GUESTFS_BOOT_ANALYSIS_H_ */
