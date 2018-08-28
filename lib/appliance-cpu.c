/* libguestfs
 * Copyright (C) 2009-2018 Red Hat Inc.
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
 * The appliance choice of CPU model.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>

#include "guestfs.h"
#include "guestfs-internal.h"

/**
 * Return the right CPU model to use as the qemu C<-cpu> parameter or
 * its equivalent in libvirt.  This returns:
 *
 * =over 4
 *
 * =item C<"host">
 *
 * The literal string C<"host"> means use C<-cpu host>.
 *
 * =item some string
 *
 * Some string such as C<"cortex-a57"> means use C<-cpu cortex-a57>.
 *
 * =item C<NULL>
 *
 * C<NULL> means no C<-cpu> option at all.  Note returning C<NULL>
 * does not indicate an error.
 *
 * =back
 *
 * This is made unnecessarily hard and fragile because of two stupid
 * choices in QEMU:
 *
 * =over 4
 *
 * =item *
 *
 * The default for C<qemu-system-aarch64 -M virt> is to emulate a
 * C<cortex-a15> (WTF?).
 *
 * =item *
 *
 * We don't know for sure if KVM will work, but C<-cpu host> is broken
 * with TCG, so we almost always pass a broken C<-cpu> flag if KVM is
 * semi-broken in any way.
 *
 * =back
 */
const char *
guestfs_int_get_cpu_model (int kvm)
{
#if defined(__aarch64__)
  /* With -M virt, the default -cpu is cortex-a15.  Stupid. */
  if (kvm)
    return "host";
  else
    return "cortex-a57";
#elif defined(__powerpc64__)
  /* See discussion in https://bugzilla.redhat.com/show_bug.cgi?id=1605071 */
  return NULL;
#else
  /* On most architectures, it is faster to pass the CPU host model to
   * the appliance, allowing maximum speed for things like checksums
   * and encryption.  Only do this with KVM.  It is broken in subtle
   * ways on TCG, and fairly pointless when you're emulating anyway.
   */
  if (kvm)
    return "host";
  else
    return NULL;
#endif
}
