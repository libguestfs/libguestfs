#include <stdio.h>
#include <string.h>
#include <ctype.h>

#include "everrun_utils.h"

/*
 * Remove redundant space and line break
 */
void
everrun_trim (char *origin, char *result)
{
    int i = 0;
    int len = strlen(origin);
    int j = len - 1;
    int pos = 0;
    while (origin[i] != '\0' && isspace(origin[i]))
    {
        ++i;
    }
    while (origin[j] != '\0' && isspace(origin[j]))
    {
        --j;
    }
    while (i <= j)
    {
        result[pos++] = origin[i++];
    }
    result[pos] = '\0';
}

/*
 * Get the obj id from the xml node (e.g.
 * storagegroup:o81 => :o81)
 */
void
get_everrun_obj_id (char *mixed_id, char *id)
{
  int i = 0;
  int len = strlen(mixed_id);
  int j = len - 1;
  int pos = 0;
  while (mixed_id[i] != '\0' && mixed_id[i] != ':')
  {
    ++i;
  }
  while (i <= j)
  {
    id[pos++] = mixed_id[i++];
  }
  id[pos] = '\0';
}

/*
 * Get the EverRun password
 */
void
get_everrun_passwd (char *passwd)
{
    char salt1[] = "avance";
    char salt2[] = "EVERrun";
    char secret[] = "NNY";

    FILE *pFile  = fopen("/shared/creds/root", "r");
    if (pFile == NULL)
    {
        passwd[0] = '\0';
        return;
    }
    fseek(pFile,0,SEEK_END);
    int len = ftell(pFile) - 1;
    char pw[len + 1];
    rewind(pFile);
    fread(pw, 1, len + 1, pFile);
    pw[len] = '\0';
    fclose(pFile);

    int i;
    for (i = 0; i < len; i++)
    {
        pw[i] = pw[i] ^ salt2[i % strlen(salt2)];
        pw[i] = pw[i] ^ secret[i % strlen(secret)];
        pw[i] = pw[i] ^ salt1[i % strlen(salt1)];
    }

    strcpy(passwd, pw);
    passwd[len] = '\0';
}