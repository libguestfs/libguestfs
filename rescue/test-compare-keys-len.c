/* Test for compare_keys_len unsigned subtraction issue.
 *
 * strlen() returns size_t (unsigned). Subtracting two size_t values
 * wraps around when the second is larger. The wrapped value converted
 * to int happens to produce the correct sign on most 64-bit platforms,
 * but this is implementation-defined behavior per C standard.
 *
 * The fixed version uses a proper three-way comparison that avoids
 * unsigned subtraction entirely.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Fixed version: proper three-way comparison. */
static int
compare_keys_len (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;
  size_t len1 = strlen (key1);
  size_t len2 = strlen (key2);
  return (len1 > len2) - (len1 < len2);
}

/* Mount points come in key-value pairs (mountpoint, device).
 * qsort sorts by pairs (stride = 2 * sizeof(char *)).
 */
static int
check_sorted (const char *test_name, char **mps, size_t nr_pairs)
{
  for (size_t i = 2; i < nr_pairs * 2; i += 2) {
    if (strlen (mps[i]) < strlen (mps[i-2])) {
      fprintf (stderr, "%s: FAIL: '%s' (len %zu) came after '%s' (len %zu)\n",
               test_name, mps[i], strlen (mps[i]),
               mps[i-2], strlen (mps[i-2]));
      return -1;
    }
  }

  printf ("%s: PASS\n", test_name);
  return 0;
}

int
main (void)
{
  int failures = 0;

  /* Test 1: "/" should come before "/boot". */
  {
    char *mps[] = {
      "/boot", "/dev/sda1",
      "/", "/dev/sda2",
      NULL
    };

    qsort (mps, 2, 2 * sizeof (char *), compare_keys_len);
    failures += check_sorted ("test1: / vs /boot", mps, 2);
  }

  /* Test 2: Multiple mount points with varying lengths. */
  {
    char *mps[] = {
      "/boot/efi", "/dev/sda1",
      "/var/log", "/dev/sda5",
      "/boot", "/dev/sda2",
      "/", "/dev/sda3",
      "/home", "/dev/sda4",
      NULL
    };

    qsort (mps, 5, 2 * sizeof (char *), compare_keys_len);
    failures += check_sorted ("test2: multiple mounts", mps, 5);
  }

  /* Test 3: Already sorted input. */
  {
    char *mps[] = {
      "/", "/dev/sda1",
      "/boot", "/dev/sda2",
      "/boot/efi", "/dev/sda3",
      NULL
    };

    qsort (mps, 3, 2 * sizeof (char *), compare_keys_len);
    failures += check_sorted ("test3: already sorted", mps, 3);
  }

  /* Test 4: Single mount point. */
  {
    char *mps[] = {
      "/", "/dev/sda1",
      NULL
    };

    qsort (mps, 1, 2 * sizeof (char *), compare_keys_len);
    failures += check_sorted ("test4: single mount", mps, 1);
  }

  /* Test 5: Deep nesting. */
  {
    char *mps[] = {
      "/a/b/c/d/e", "/dev/sda5",
      "/a/b", "/dev/sda2",
      "/a", "/dev/sda1",
      "/a/b/c/d", "/dev/sda4",
      "/a/b/c", "/dev/sda3",
      NULL
    };

    qsort (mps, 5, 2 * sizeof (char *), compare_keys_len);
    failures += check_sorted ("test5: deep nesting", mps, 5);
  }

  printf ("\n");
  if (failures) {
    printf ("FAILED\n");
    return EXIT_FAILURE;
  }

  printf ("ALL TESTS PASSED\n");
  return EXIT_SUCCESS;
}
