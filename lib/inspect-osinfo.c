/* libguestfs
 * Copyright (C) 2025 Red Hat Inc.
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

#include <config.h>
#include <stdbool.h>
#include <string.h>

#include "guestfs.h"
#include "guestfs-internal.h"
#include "guestfs-internal-actions.h"

enum linux_format {
  FORMAT_ROLLING,     /* archlinux, gentoo, voidlinux */
  FORMAT_MAJOR_ONLY,  /* fedora42, debian12 */
  FORMAT_UBUNTU,      /* ubuntu22.04 */
  FORMAT_SUSE,        /* sles15sp5 to sle15sp5 */
  FORMAT_RHEL_LIKE,   /* centos9, rocky9, almalinux9 */
  FORMAT_ALT          /* alt9.2 or altlinux8.4 */
};

struct linux_rule {
  const char *distro;
  enum linux_format format;
  int min_major;      /* 0 = no restriction */
};

/* Ordered by real-world frequency */
static const struct linux_rule linux_rules[] = {
  /* Most common first */
  { "fedora",        FORMAT_MAJOR_ONLY,  0 },
  { "ubuntu",        FORMAT_UBUNTU,      0 },
  { "debian",        FORMAT_MAJOR_ONLY,  4 },  /* debian1..3 not supported */
  /* RHEL ecosystem — very common in enterprises */
  { "rhel",          FORMAT_RHEL_LIKE,   6 },
  { "centos",        FORMAT_RHEL_LIKE,   6 },
  { "rocky",         FORMAT_RHEL_LIKE,   8 },
  { "almalinux",     FORMAT_RHEL_LIKE,   8 },
  { "oraclelinux",   FORMAT_RHEL_LIKE,   6 },
  { "eurolinux",     FORMAT_RHEL_LIKE,   8 },
  { "circle",        FORMAT_RHEL_LIKE,   8 },  /* Circle Linux = RHEL 8/9 clone */
  /* SUSE */
  { "sles",          FORMAT_SUSE,        0 },
  /* Rolling release */
  { "archlinux",     FORMAT_ROLLING,     0 },
  { "gentoo",        FORMAT_ROLLING,     0 },
  { "voidlinux",     FORMAT_ROLLING,     0 },
  /* Others */
  { "mageia",        FORMAT_MAJOR_ONLY,  0 },
  { "altlinux",      FORMAT_ALT,         0 },
  /* Mandriva/Mandrake successors sometimes detected as "mandriva" or "mandrake" */
  { "mandriva",      FORMAT_MAJOR_ONLY,  0 },
  { "mandrake",      FORMAT_MAJOR_ONLY,  0 },
  /* OpenMandriva */
  { "openmandriva",  FORMAT_MAJOR_ONLY,  0 },
  /* Red Hat Enterprise Linux derivatives that sometimes report as "redhat" */
  { "redhat",        FORMAT_RHEL_LIKE,   6 },
  /* Scientific Linux (EOL but still seen) */
  { "scientificlinux", FORMAT_RHEL_LIKE, 6 },
  { "scientific",    FORMAT_RHEL_LIKE,   6 },
  /* ClearOS (CentOS/RHEL based) */
  { "clearos",       FORMAT_RHEL_LIKE,   6 },
  /* Springdale Linux (formerly Princeton) */
  { "springdale",    FORMAT_RHEL_LIKE,   6 },
  { NULL, 0, 0 }
};

struct windows_version {
  int major;
  int minor;
  const char *server;
  const char *client;
};

static const struct windows_version windows_versions[] = {
  { 5, 1, NULL,      "winxp" },
  { 5, 2, "win2k3",  "winxp" },
  { 6, 0, "win2k8",  "winvista" },
  { 6, 1, "win2k8r2","win7" },
  { 6, 2, "win2k12", "win8" },
  { 6, 3, "win2k12r2","win8.1" },
  { 10,0, "win2k16", "win10" },
  { 0, 0, NULL, NULL }
};

typedef char *(*os_handler)(guestfs_h *g, const char *root,
                            const char *type, const char *distro,
                            int major, int minor);

static char *handle_linux   (guestfs_h *g, const char *root, const char *type,
                             const char *distro, int major, int minor);
static char *handle_windows (guestfs_h *g, const char *root, const char *type,
                             const char *distro, int major, int minor);
static char *handle_bsd     (guestfs_h *g, const char *root, const char *type,
                             const char *distro, int major, int minor);
static char *handle_msdos   (guestfs_h *g, const char *root, const char *type,
                             const char *distro, int major, int minor);
static char *handle_generic (guestfs_h *g, const char *root, const char *type,
                             const char *distro, int major, int minor);

struct os_rule {
  const char *type;
  const char *distro;   /* NULL = wildcard */
  os_handler handler;
};

static const struct os_rule dispatch[] = {
  { "linux",    NULL, handle_linux },
  { "windows",  NULL, handle_windows },
  { "freebsd",  NULL, handle_bsd },
  { "netbsd",   NULL, handle_bsd },
  { "openbsd",  NULL, handle_bsd },
  { "dos",      "msdos", handle_msdos },
  { NULL,       NULL, handle_generic },
  { NULL,       NULL, NULL }
};

char *
guestfs_impl_inspect_get_osinfo (guestfs_h *g, const char *root)
{
  CLEANUP_FREE char *type = guestfs_inspect_get_type (g, root);
  if (!type)
    return NULL;
  CLEANUP_FREE char *distro = guestfs_inspect_get_distro (g, root);
  if (!distro)
    return NULL;
  const int major = guestfs_inspect_get_major_version (g, root);
  const int minor = guestfs_inspect_get_minor_version (g, root);

  for (const struct os_rule *r = dispatch; r->handler; ++r) {
    if (r->type && !STREQ(type, r->type))
      continue;
    if (r->distro && !STREQ(distro, r->distro))
      continue;
    char *result = r->handler(g, root, type, distro, major, minor);
    if (result)
      return result;
  }
  return safe_strdup(g, "unknown");
}

static char *
handle_linux (guestfs_h *g, const char *root, const char *type,
              const char *distro, int major, int minor)
{
  /* Main table lookup */
  for (const struct linux_rule *r = linux_rules; r->distro; ++r) {
    if (!STREQ(distro, r->distro))
      continue;
    if (major > 0 && r->min_major > 0 && major < r->min_major)
      continue;
    switch (r->format) {
    case FORMAT_ROLLING:
      return safe_strdup (g, distro);
    case FORMAT_MAJOR_ONLY:
      if (major <= 0) return NULL;
      return safe_asprintf (g, "%s%d", distro, major);
    case FORMAT_UBUNTU:
      return safe_asprintf (g, "%s%d.%02d", distro, major, minor);
    case FORMAT_SUSE: {
      const char *base = (major >= 15 || (major == 12 && minor >= 1)) ? "sle" : "sles";
      if (minor == 0)
        return safe_asprintf (g, "%s%d", base, major);
      else
        return safe_asprintf (g, "%s%dsp%d", base, major, minor);
    }
    case FORMAT_RHEL_LIKE:
      if (major >= 8)
        return safe_asprintf (g, "%s%d", distro, major);
      if (major == 7)
        return safe_asprintf (g, "%s%d.0", distro, major);
      if (major == 6)
        return safe_asprintf (g, "%s%d.%d", distro, major, minor);
      return NULL;
    case FORMAT_ALT:
      if (major >= 8)
        return safe_asprintf (g, "alt%d.%d", major, minor);
      else
        return safe_asprintf (g, "%s%d.%d", distro, major, minor);
    default:
      return NULL;
    }
  }
  /* Absolute fallback for completely unknown but versioned Linux */
  if (STRNEQ (distro, "unknown") && major > 0)
    return safe_asprintf (g, "%s%d.%d", distro, major, minor);
  return NULL;
}

static char *
handle_windows (guestfs_h *g, const char *root, const char *type,
                const char *distro, int major, int minor)
{
  CLEANUP_FREE char *product_name = guestfs_inspect_get_product_name(g, root);
  CLEANUP_FREE char *product_variant = guestfs_inspect_get_product_variant(g, root);
  if (!product_name || !product_variant)
    return NULL;
  const bool is_server = strstr(product_variant, "Server") != NULL;

  /* Windows 10/11 and modern Server */
  if (major == 10 && minor == 0) {
    if (is_server) {
      if (strstr(product_name, "2025")) return safe_strdup(g, "win2k25");
      if (strstr(product_name, "2022")) return safe_strdup(g, "win2k22");
      if (strstr(product_name, "2019")) return safe_strdup(g, "win2k19");
      return safe_strdup(g, "win2k16");
    }
    /* For Windows >= 10 Client we can only distinguish between
     * https://github.com/cygwin/cygwin/blob/a263fe0b268580273c1adc4b1bad256147990222/winsup/cygwin/wincap.cc#L429
     */
    CLEANUP_FREE char *build = guestfs_inspect_get_build_id(g, root);
    int b = build ? guestfs_int_parse_unsigned_int(g, build) : -1;
    return safe_strdup(g, b >= 22000 ? "win11" : "win10");
  }

  /* XP x64 vs Server 2003 */
  if (major == 5 && minor == 2 && !is_server) {
    if (strstr(product_name, "XP")) return safe_strdup(g, "winxp");
    if (strstr(product_name, "R2")) return safe_strdup(g, "win2k3r2");
    return safe_strdup(g, "win2k3");
  }

  /* Standard mapping */
  for (const struct windows_version *v = windows_versions; v->major; ++v) {
    if (v->major == major && v->minor == minor) {
      const char *id = is_server ? v->server : v->client;
      return id ? safe_strdup(g, id) : NULL;
    }
  }
  return NULL;
}

static char *
handle_bsd (guestfs_h *g, const char *root, const char *type,
            const char *distro, int major, int minor)
{
  return major > 0 ? safe_asprintf(g, "%s%d.%d", type, major, minor) : NULL;
}

static char *
handle_msdos (guestfs_h *g, const char *root, const char *type,
              const char *distro, int major, int minor)
{
  return safe_strdup(g, "msdos6.22");
}

static char *
handle_generic (guestfs_h *g, const char *root, const char *type,
                const char *distro, int major, int minor)
{
  if (STRNEQ(distro, "unknown") && major > 0)
    return safe_asprintf(g, "%s%d.%d", distro, major, minor);
  return NULL;
}
