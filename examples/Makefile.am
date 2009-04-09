# libguestfs examples

noinst_PROGRAMS = df hello

df_SOURCES = df.c
df_CFLAGS = -I$(top_builddir)/src -Wall
df_LDADD = $(top_builddir)/src/libguestfs.la

hello_SOURCES = hello.c
hello_CFLAGS = -I$(top_builddir)/src -Wall
hello_LDADD = $(top_builddir)/src/libguestfs.la

CLEANFILES = *~
