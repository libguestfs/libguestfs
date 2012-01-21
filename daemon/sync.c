/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009-2012 Red Hat Inc.
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

#ifdef HAVE_WINDOWS_H
#include <windows.h>
#endif

#include <stdio.h>
#include <unistd.h>

#include "daemon.h"
#include "actions.h"

#ifdef WIN32
static int sync_win32 (void);
#endif

int
do_sync (void)
{
  if (sync_disks () == -1) {
    reply_with_perror ("sync");
    return -1;
  }

  return 0;
}

/* This is a replacement for sync(2) which is called from
 * this file and from other places in the daemon.  It works
 * on Windows too.
 */
int
sync_disks (void)
{
#if defined(HAVE_SYNC)
  sync ();
  return 0;
#elif defined(WIN32)
  return sync_win32 ();
#else
#error "no known sync() API"
#endif
}

#ifdef WIN32
static int
sync_win32 (void)
{
  DWORD n1, n2;

  n1 = GetLogicalDriveStrings (0, NULL);
  if (n1 == 0)
    return -1;

  TCHAR buffer[n1+2]; /* sic */
  n2 = GetLogicalDriveStrings (n1, buffer);
  if (n2 == 0)
    return -1;

  TCHAR *p = buffer;

  /* The MSDN example code itself assumes that there is always one
   * drive in the system.  However we will be better than that and not
   * make the assumption ...
   */
  while (*p) {
    HANDLE drive;
    DWORD drive_type;

    /* Ignore removable drives. */
    drive_type = GetDriveType (p);
    if (drive_type == DRIVE_FIXED) {
      /* To open the volume you have to specify the volume name, not
       * the mount point.  MSDN documents use of the constant 50
       * below.
       */
      TCHAR volname[50];
      if (!GetVolumeNameForVolumeMountPoint (p, volname, 50))
        return -1;

      drive = CreateFile (volname, GENERIC_READ|GENERIC_WRITE,
                          FILE_SHARE_READ|FILE_SHARE_WRITE,
                          NULL, OPEN_EXISTING, 0, 0);
      if (drive == INVALID_HANDLE_VALUE)
        return -1;

      BOOL r;
      /* This always fails in Wine:
       * http://bugs.winehq.org/show_bug.cgi?id=14915
       */
      r = FlushFileBuffers (drive);
      CloseHandle (drive);
      if (!r)
        return -1;
    }

    /* Skip to next \0 character. */
    while (*p++);
  }

  return 0;
}
#endif /* WIN32 */
