# libguestfs examples

noinst_PROGRAMS = hello

hello_SOURCES = hello.c
hello_CFLAGS = -I$(top_builddir)/src -Wall
hello_LDADD = $(top_builddir)/src/libguestfs.la

CLEANFILES = *~ $(noinst_PROGRAMS)
