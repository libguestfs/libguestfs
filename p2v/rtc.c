/* virt-p2v
 * Copyright (C) 2017 Red Hat Inc.
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
 * Try to calculate Real Time Clock (RTC) offset from UTC in seconds.
 * For example if the RTC is 1 hour ahead of UTC, this will return
 * C<3600>.  This is stored in C<config-E<gt>rtc_offset>.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <fcntl.h>
#include <errno.h>
#include <libintl.h>
#include <time.h>
#include <sys/ioctl.h>

#include <math.h>

#ifdef HAVE_LINUX_RTC_H
#include <linux/rtc.h>
#endif

#include "getprogname.h"
#include "ignore-value.h"

#include "p2v.h"

#ifndef HAVE_LINUX_RTC_H
void
get_rtc_config (struct rtc_config *rtc)
{
  fprintf (stderr, "%s: RTC: compiled without support for /dev/rtc\n",
           getprogname ());

  rtc->offset = 0;
  rtc->basis = BASIS_UTC;
}

#else /* HAVE_LINUX_RTC_H */

/**
 * Return RTC offset from UTC in seconds, positive numbers meaning
 * that the RTC is running ahead of UTC.
 *
 * In the error case, C<rtcE<gt>offset> is updated with 0 and
 * C<rtcE<gt>basis> is set to C<BASIS_UNKNOWN>.
 */
void
get_rtc_config (struct rtc_config *rtc)
{
  int fd;
  struct rtc_time rtm;
  struct tm tm;
  time_t rtc_time;
  time_t system_time;
  double rf;

  rtc->basis = BASIS_UNKNOWN;
  rtc->offset = 0;

  fd = open ("/dev/rtc", O_RDONLY);
  if (fd == -1) {
    perror ("/dev/rtc");
    return;
  }

  if (ioctl (fd, RTC_RD_TIME, &rtm) == -1) {
    perror ("ioctl: RTC_RD_TIME");
    close (fd);
    return;
  }

  close (fd);

#ifdef DEBUG_STDERR
  fprintf (stderr, "%s: RTC: %04d-%02d-%02d %02d:%02d:%02d\n",
           getprogname (),
           rtm.tm_year + 1900, rtm.tm_mon + 1, rtm.tm_mday,
           rtm.tm_hour, rtm.tm_min, rtm.tm_sec);
#endif

  /* Convert this to seconds since the epoch. */
  tm.tm_sec = rtm.tm_sec;
  tm.tm_min = rtm.tm_min;
  tm.tm_hour = rtm.tm_hour;
  tm.tm_mday = rtm.tm_mday;
  tm.tm_mon = rtm.tm_mon;
  tm.tm_year = rtm.tm_year;
  tm.tm_isdst = 0;              /* Ignore DST when calculating. */
  rtc_time = timegm (&tm);
  if (rtc_time == -1)
    return;                     /* Not representable as a Unix time. */

  /* Get system time in UTC. */
  system_time = time (NULL);

  /* Calculate the difference, rounded to the nearest 15 minutes. */
  rf = rtc_time - system_time;

#ifdef DEBUG_STDERR
  fprintf (stderr, "%s: RTC: %ld system time: %ld difference: %g\n",
           getprogname (),
           (long) rtc_time, (long) system_time, rf);
#endif

  rf /= 15*60;
  rf = round (rf);
  rf *= 15*60;

  /* If it's obviously out of range then print an error and return. */
  if (rf < -12*60*60 || rf > 14*60*60) {
    fprintf (stderr,
             "%s: RTC: offset of RTC from UTC is out of range (%g).\n",
             getprogname (), rf);
    return;
  }

  rtc->offset = (int) rf;

#ifdef DEBUG_STDERR
  fprintf (stderr, "%s: RTC: offset of RTC from UTC = %d secs\n",
           getprogname (), rtc->offset);
#endif

  /* Is the hardware clock set to localtime?
   *
   * Unfortunately it's not possible to distinguish between UTC and
   * localtime in timezones that lie along the Greenwich Meridian
   * (obviously including the UK), when daylight savings time is not
   * in effect.  In that case, prefer UTC.
   */
  localtime_r (&system_time, &tm);
  if (tm.tm_gmtoff != 0 && tm.tm_gmtoff != rtc->offset)
    rtc->basis = BASIS_UTC;
  else {
    rtc->basis = BASIS_LOCALTIME;
    rtc->offset = 0;
#ifdef DEBUG_STDERR
    fprintf (stderr, "%s: RTC time is localtime\n", getprogname ());
#endif
  }

  return;
}

#endif /* HAVE_LINUX_RTC_H */
