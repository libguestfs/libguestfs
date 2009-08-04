# Customize Makefile.maint.                           -*- makefile -*-
# Copyright (C) 2003-2009 Free Software Foundation, Inc.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Use alpha.gnu.org for alpha and beta releases.
# Use ftp.gnu.org for major releases.
gnu_ftp_host-alpha = alpha.gnu.org
gnu_ftp_host-beta = alpha.gnu.org
gnu_ftp_host-major = ftp.gnu.org
gnu_rel_host = $(gnu_ftp_host-$(RELEASE_TYPE))

url_dir_list = \
  ftp://$(gnu_rel_host)/gnu/coreutils

# Tests not to run as part of "make distcheck".
local-checks-to-skip =			\
  sc_po_check				\
  changelog-check			\
  check-AUTHORS				\
  makefile-check			\
  makefile_path_separator_check		\
  patch-check				\
  sc_GPL_version			\
  sc_always_defined_macros		\
  sc_cast_of_alloca_return_value	\
  sc_dd_max_sym_length			\
  sc_error_exit_success			\
  sc_file_system			\
  sc_immutable_NEWS			\
  sc_makefile_path_separator_check	\
  sc_obsolete_symbols			\
  sc_prohibit_S_IS_definition		\
  sc_prohibit_atoi_atof			\
  sc_prohibit_jm_in_m4			\
  sc_prohibit_quote_without_use		\
  sc_prohibit_quotearg_without_use	\
  sc_prohibit_stat_st_blocks		\
  sc_prohibit_strcmp_and_strncmp	\
  sc_prohibit_strcmp			\
  sc_root_tests				\
  sc_space_tab				\
  sc_sun_os_names			\
  sc_system_h_headers			\
  sc_tight_scope			\
  sc_two_space_separator_in_usage	\
  sc_error_message_uppercase		\
  sc_program_name			\
  sc_require_test_exit_idiom		\
  sc_makefile_check			\
  $(disable_temporarily)		\
  sc_useless_cpp_parens

disable_temporarily =			\
  sc_makefile_TAB_only_indentation	\
  sc_unmarked_diagnostics		\
  sc_prohibit_ctype_h			\
  sc_prohibit_asprintf			\
  sc_m4_quote_check			\
  sc_prohibit_trailing_blank_lines	\
  sc_avoid_ctype_macros			\
  sc_avoid_write

# Avoid uses of write(2).  Either switch to streams (fwrite), or use
# the safewrite wrapper.
sc_avoid_write:
	@if $(VC_LIST_EXCEPT) | grep '\.c$$' > /dev/null; then		\
	  grep '\<write *(' $$($(VC_LIST_EXCEPT) | grep '\.c$$') &&	\
	    { echo "$(ME): the above files use write;"			\
	      " consider using the safewrite wrapper instead"		\
		  1>&2; exit 1; } || :;					\
	else :;								\
	fi

# Use STREQ rather than comparing strcmp == 0, or != 0.
# Similarly, use STREQLEN or STRPREFIX rather than strncmp.
sc_prohibit_strcmp_and_strncmp:
	@grep -nE '! *strn?cmp *\(|\<strn?cmp *\([^)]+\) *=='		\
	    $$($(VC_LIST_EXCEPT))					\
	  | grep -vE ':# *define STREQ(LEN)?\(' &&			\
	  { echo '$(ME): use STREQ(LEN) in place of the above uses of strcmp(strncmp)' \
		1>&2; exit 1; } || :

# Use virAsprintf rather than a'sprintf since *strp is undefined on error.
sc_prohibit_asprintf:
	@re='\<[a]sprintf\>'						\
	msg='use virAsprintf, not a'sprintf				\
	  $(_prohibit_regexp)

# Prohibit the inclusion of <ctype.h>.
sc_prohibit_ctype_h:
	@grep -E '^# *include  *<ctype\.h>' $$($(VC_LIST_EXCEPT)) &&	\
	  { echo "$(ME): don't use ctype.h; instead, use c-ctype.h"	\
		1>&2; exit 1; } || :

# Ensure that no C source file uses TABs for indentation.
# Exclude some version-controlled symlinks.
sc_TAB_in_indentation:
	@grep -lE '^ *	' /dev/null					\
	     $$($(VC_LIST_EXCEPT)) &&					\
	  { echo '$(ME): found TAB(s) used for indentation in C sources;'\
	      'use spaces' 1>&2; exit 1; } || :

ctype_re = isalnum|isalpha|isascii|isblank|iscntrl|isdigit|isgraph|islower\
|isprint|ispunct|isspace|isupper|isxdigit|tolower|toupper

sc_avoid_ctype_macros:
	@grep -E '\b($(ctype_re)) *\(' /dev/null			\
	     $$($(VC_LIST_EXCEPT)) &&					\
	  { echo "$(ME): don't use ctype macros (use c-ctype.h)"	\
		1>&2; exit 1; } || :

sc_prohibit_virBufferAdd_with_string_literal:
	@re='\<virBufferAdd *\([^,]+, *"[^"]'				\
	msg='use virBufferAddLit, not virBufferAdd, with a string literal' \
	  $(_prohibit_regexp)

# Not only do they fail to deal well with ipv6, but the gethostby*
# functions are also not thread-safe.
sc_prohibit_gethostby:
	@re='\<gethostby(addr|name2?) *\('				\
	msg='use getaddrinfo, not gethostby*'				\
	  $(_prohibit_regexp)

# Disallow trailing blank lines.
sc_prohibit_trailing_blank_lines:
	@$(VC_LIST_EXCEPT) | xargs perl -ln -0777 -e			\
	  '/\n\n+$$/ and print $$ARGV' > $@-t
	@found=0; test -s $@-t && { found=1; cat $@-t 1>&2;		\
	  echo '$(ME): found trailing blank line(s)' 1>&2; };		\
	rm -f $@-t;							\
	test $$found = 0

# We don't use this feature of maint.mk.
prev_version_file = /dev/null

ifeq (0,$(MAKELEVEL))
  _curr_status = .git-module-status
  # The sed filter accommodates those who check out on a commit from which
  # no tag is reachable.  In that case, git submodule status prints a "-"
  # in column 1 and does not print a "git describe"-style string after the
  # submodule name.  Contrast these:
  # -b653eda3ac4864de205419d9f41eec267cb89eeb .gnulib
  #  b653eda3ac4864de205419d9f41eec267cb89eeb .gnulib (v0.0-2286-gb653eda)
  _submodule_hash = sed 's/.//;s/ .*//'
  _update_required := $(shell						\
      actual=$$(git submodule status | $(_submodule_hash));		\
      stamp="$$($(_submodule_hash) $(_curr_status) 2>/dev/null)";	\
      test "$$stamp" = "$$actual"; echo $$?)
  ifeq (1,$(_update_required))
    $(error gnulib update required; run ./autogen.sh first)
  endif
endif
