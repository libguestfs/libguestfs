/* libguestfs - guestfish shell
 * Copyright (C) 2010 Red Hat Inc.
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

#ifndef FISH_RMSD_H
#define FISH_RMSD_H

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

#endif /* FISH_RMSD_H */
