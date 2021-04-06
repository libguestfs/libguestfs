/* Note the license of this file is "GPL".  It is used in the daemon
 * and in guestfish which have a compatible license.
 */

#define __strtol strtoll
#define __strtol_t long long int
#define __xstrtol xstrtoll
#define STRTOL_T_MINIMUM LLONG_MIN
#define STRTOL_T_MAXIMUM LLONG_MAX
#include "xstrtol.c"
