/* virt-p2v
 * Copyright (C) 2009-2019 Red Hat Inc.
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

/**
 * This file implements almost all of the virt-p2v graphical user
 * interface (GUI).
 *
 * The GUI has three main dialogs:
 *
 * =over 4
 *
 * =item Connection dialog
 *
 * The connection dialog is the one shown initially.  It asks the user
 * to type in the login details for the remote conversion server and
 * invites the user to test the ssh connection.
 *
 * =item Conversion dialog
 *
 * The conversion dialog asks for information about the target VM
 * (eg. the number of vCPUs required), and about what to convert
 * (eg. which network interfaces should be copied and which should be
 * ignored).
 *
 * =item Running dialog
 *
 * The running dialog is displayed when the P2V process is underway.
 * It mainly displays the virt-v2v debug messages.
 *
 * =back
 *
 * Note that the other major dialog (C<"Configure network ...">) is
 * handled entirely by NetworkManager's L<nm-connection-editor(1)>
 * program and has nothing to do with this code.
 *
 * This file is written in a kind of "pseudo-Gtk" which is backwards
 * compatible from Gtk 2.10 (RHEL 5) through at least Gtk 3.22.  This
 * is done using a few macros to implement old C<gtk_*> functions or
 * map them to newer functions.  Supporting ancient Gtk is important
 * because we want to provide a virt-p2v binary that can run on very
 * old kernels, to support 32 bit and proprietary SCSI drivers.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <error.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>

#include <pthread.h>

/* errors in <gtk.h> */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wstrict-prototypes"
#if defined(__GNUC__) && __GNUC__ >= 6 /* gcc >= 6 */
#pragma GCC diagnostic ignored "-Wshift-overflow"
#endif
#include <gtk/gtk.h>
#pragma GCC diagnostic pop

#include "ignore-value.h"
#include "getprogname.h"

#include "p2v.h"

/* See note about "pseudo-Gtk" above. */
#include "gui-gtk2-compat.h"
#include "gui-gtk3-compat.h"

/* Maximum vCPUs and guest memory that we will allow users to set.
 * These limits come from
 * https://access.redhat.com/articles/rhel-kvm-limits
 */
#define MAX_SUPPORTED_VCPUS 160
#define MAX_SUPPORTED_MEMORY_MB (UINT64_C (4000 * 1024))

#if GLIB_CHECK_VERSION(2,32,0) && GTK_CHECK_VERSION(3,12,0)   /* glib >= 2.32 && gtk >= 3.12 */
#define USE_POPOVERS
#endif

static void create_connection_dialog (struct config *);
static void create_conversion_dialog (struct config *);
static void create_running_dialog (void);
static void show_connection_dialog (void);
static void show_conversion_dialog (void);
static void show_running_dialog (void);

static void set_info_label (void);

/* The connection dialog. */
static GtkWidget *conn_dlg,
  *server_entry, *port_entry,
  *username_entry, *password_entry, *identity_entry, *sudo_button,
  *spinner_hbox,
#ifdef GTK_SPINNER
  *spinner,
#endif
  *spinner_message, *next_button;

/* The conversion dialog. */
static GtkWidget *conv_dlg,
  *guestname_entry, *vcpus_entry, *memory_entry,
  *vcpus_warning, *memory_warning, *target_warning_label,
  *o_combo, *oc_entry, *os_entry, *of_entry, *oa_combo,
  *info_label,
  *disks_list, *removable_list, *interfaces_list,
  *start_button;

/* The running dialog which is displayed when virt-v2v is running. */
static GtkWidget *run_dlg,
  *v2v_output_sw, *v2v_output, *log_label, *status_label,
  *cancel_button, *shutdown_button;

/* Colour tags used in the v2v_output GtkTextBuffer. */
static GtkTextTag *v2v_output_tags[16];

#if !GTK_CHECK_VERSION(3,0,0)   /* gtk < 3 */
/* The license of virt-p2v, for the About dialog. */
static const char gplv2plus[] =
  "This program is free software; you can redistribute it and/or modify\n"
  "it under the terms of the GNU General Public License as published by\n"
  "the Free Software Foundation; either version 2 of the License, or\n"
  "(at your option) any later version.\n"
  "\n"
  "This program is distributed in the hope that it will be useful,\n"
  "but WITHOUT ANY WARRANTY; without even the implied warranty of\n"
  "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\n"
  "GNU General Public License for more details.\n"
  "\n"
  "You should have received a copy of the GNU General Public License\n"
  "along with this program; if not, write to the Free Software\n"
  "Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.\n";
#endif

/**
 * The entry point from the main program.
 *
 * Note that C<gtk_init> etc have already been called in C<main>.
 */
void
gui_conversion (struct config *config)
{
  /* Create the dialogs. */
  create_connection_dialog (config);
  create_conversion_dialog (config);
  create_running_dialog ();

  /* Start by displaying the connection dialog. */
  show_connection_dialog ();

  gtk_main ();
}

/*----------------------------------------------------------------------*/
/* Connection dialog. */

static void username_changed_callback (GtkWidget *w, gpointer data);
static void password_or_identity_changed_callback (GtkWidget *w, gpointer data);
static void test_connection_clicked (GtkWidget *w, gpointer data);
static void *test_connection_thread (void *data);
static gboolean start_spinner (gpointer user_data);
static gboolean stop_spinner (gpointer user_data);
static gboolean test_connection_error (gpointer user_data);
static gboolean test_connection_ok (gpointer user_data);
static void configure_network_button_clicked (GtkWidget *w, gpointer data);
static void xterm_button_clicked (GtkWidget *w, gpointer data);
static void about_button_clicked (GtkWidget *w, gpointer data);
static void connection_next_clicked (GtkWidget *w, gpointer data);
static void repopulate_output_combo (struct config *config);

/**
 * Create the connection dialog.
 *
 * This creates the dialog, but it is not displayed.  See
 * C<show_connection_dialog>.
 */
static void
create_connection_dialog (struct config *config)
{
  GtkWidget *intro, *table;
  GtkWidget *server_label;
  GtkWidget *server_hbox;
  GtkWidget *port_colon_label;
  GtkWidget *username_label;
  GtkWidget *password_label;
  GtkWidget *identity_label;
  GtkWidget *test_hbox, *test;
  GtkWidget *about;
  GtkWidget *configure_network;
  GtkWidget *xterm;
  char port_str[64];

  conn_dlg = gtk_dialog_new ();
  gtk_window_set_title (GTK_WINDOW (conn_dlg), getprogname ());
  gtk_window_set_resizable (GTK_WINDOW (conn_dlg), FALSE);

  /* The main dialog area. */
  intro = gtk_label_new (_("Connect to a virt-v2v conversion server over SSH:"));
  gtk_label_set_line_wrap (GTK_LABEL (intro), TRUE);
  set_padding (intro, 10, 10);

  table_new (table, 5, 2);
  server_label = gtk_label_new_with_mnemonic (_("Conversion _server:"));
  table_attach (table, server_label,
                0, 1, 0, 1, GTK_FILL, GTK_FILL, 4, 4);
  set_alignment (server_label, 1., 0.5);

  hbox_new (server_hbox, FALSE, 4);
  server_entry = gtk_entry_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (server_label), server_entry);
  if (config->remote.server != NULL)
    gtk_entry_set_text (GTK_ENTRY (server_entry), config->remote.server);
  port_colon_label = gtk_label_new (":");
  port_entry = gtk_entry_new ();
  gtk_entry_set_width_chars (GTK_ENTRY (port_entry), 6);
  snprintf (port_str, sizeof port_str, "%d", config->remote.port);
  gtk_entry_set_text (GTK_ENTRY (port_entry), port_str);
  gtk_box_pack_start (GTK_BOX (server_hbox), server_entry, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (server_hbox), port_colon_label, FALSE, FALSE, 0);
  gtk_box_pack_start (GTK_BOX (server_hbox), port_entry, FALSE, FALSE, 0);
  table_attach (table, server_hbox,
                1, 2, 0, 1, GTK_EXPAND|GTK_FILL, GTK_FILL, 4, 4);

  username_label = gtk_label_new_with_mnemonic (_("_User name:"));
  table_attach (table, username_label,
                0, 1, 1, 2, GTK_FILL, GTK_FILL, 4, 4);
  set_alignment (username_label, 1., 0.5);
  username_entry = gtk_entry_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (username_label), username_entry);
  if (config->auth.username != NULL)
    gtk_entry_set_text (GTK_ENTRY (username_entry), config->auth.username);
  else
    gtk_entry_set_text (GTK_ENTRY (username_entry), "root");
  table_attach (table, username_entry,
                1, 2, 1, 2, GTK_EXPAND|GTK_FILL, GTK_FILL, 4, 4);

  password_label = gtk_label_new_with_mnemonic (_("_Password:"));
  table_attach (table, password_label,
                0, 1, 2, 3, GTK_FILL, GTK_FILL, 4, 4);
  set_alignment (password_label, 1., 0.5);
  password_entry = gtk_entry_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (password_label), password_entry);
  gtk_entry_set_visibility (GTK_ENTRY (password_entry), FALSE);
#ifdef GTK_INPUT_PURPOSE_PASSWORD
  gtk_entry_set_input_purpose (GTK_ENTRY (password_entry),
                               GTK_INPUT_PURPOSE_PASSWORD);
#endif
  if (config->auth.password != NULL)
    gtk_entry_set_text (GTK_ENTRY (password_entry), config->auth.password);
  table_attach (table, password_entry,
                1, 2, 2, 3, GTK_EXPAND|GTK_FILL, GTK_FILL, 4, 4);

  identity_label = gtk_label_new_with_mnemonic (_("SSH _Identity URL:"));
  table_attach (table, identity_label,
                0, 1, 3, 4, GTK_FILL, GTK_FILL, 4, 4);
  set_alignment (identity_label, 1., 0.5);
  identity_entry = gtk_entry_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (identity_label), identity_entry);
  if (config->auth.identity.url != NULL)
    gtk_entry_set_text (GTK_ENTRY (identity_entry), config->auth.identity.url);
  table_attach (table, identity_entry,
                1, 2, 3, 4, GTK_EXPAND|GTK_FILL, GTK_FILL, 4, 4);

  sudo_button =
    gtk_check_button_new_with_mnemonic (_("Use su_do when running virt-v2v"));
  gtk_toggle_button_set_active (GTK_TOGGLE_BUTTON (sudo_button),
                                config->auth.sudo);
  table_attach (table, sudo_button,
                1, 2, 4, 5, GTK_FILL, GTK_FILL, 4, 4);

  hbox_new (test_hbox, FALSE, 0);
  test = gtk_button_new_with_mnemonic (_("_Test connection"));
  gtk_box_pack_start (GTK_BOX (test_hbox), test, TRUE, FALSE, 0);

  hbox_new (spinner_hbox, FALSE, 10);
#ifdef GTK_SPINNER
  spinner = gtk_spinner_new ();
  gtk_box_pack_start (GTK_BOX (spinner_hbox), spinner, FALSE, FALSE, 0);
#endif
  spinner_message = gtk_label_new (NULL);
  gtk_label_set_line_wrap (GTK_LABEL (spinner_message), TRUE);
  set_padding (spinner_message, 10, 10);
  gtk_box_pack_start (GTK_BOX (spinner_hbox), spinner_message, TRUE, TRUE, 0);

  gtk_box_pack_start
    (GTK_BOX (gtk_dialog_get_content_area (GTK_DIALOG (conn_dlg))),
     intro, TRUE, TRUE, 0);
  gtk_box_pack_start
    (GTK_BOX (gtk_dialog_get_content_area (GTK_DIALOG (conn_dlg))),
     table, TRUE, TRUE, 0);
  gtk_box_pack_start
    (GTK_BOX (gtk_dialog_get_content_area (GTK_DIALOG (conn_dlg))),
     test_hbox, FALSE, FALSE, 0);
  gtk_box_pack_start
    (GTK_BOX (gtk_dialog_get_content_area (GTK_DIALOG (conn_dlg))),
     spinner_hbox, TRUE, TRUE, 0);

  /* Buttons. */
  gtk_dialog_add_buttons (GTK_DIALOG (conn_dlg),
                          _("_Configure network ..."), 1,
                          _("_XTerm ..."), 2,
                          _("_About virt-p2v " PACKAGE_VERSION " ..."), 3,
                          _("_Next"), 4,
                          NULL);

  next_button = gtk_dialog_get_widget_for_response (GTK_DIALOG (conn_dlg), 4);
  gtk_widget_set_sensitive (next_button, FALSE);

  configure_network =
    gtk_dialog_get_widget_for_response (GTK_DIALOG (conn_dlg), 1);
  xterm = gtk_dialog_get_widget_for_response (GTK_DIALOG (conn_dlg), 2);
  about = gtk_dialog_get_widget_for_response (GTK_DIALOG (conn_dlg), 3);

  /* Signals. */
  g_signal_connect_swapped (G_OBJECT (conn_dlg), "destroy",
                            G_CALLBACK (gtk_main_quit), NULL);
  g_signal_connect (G_OBJECT (test), "clicked",
                    G_CALLBACK (test_connection_clicked), config);
  g_signal_connect (G_OBJECT (configure_network), "clicked",
                    G_CALLBACK (configure_network_button_clicked), NULL);
  g_signal_connect (G_OBJECT (xterm), "clicked",
                    G_CALLBACK (xterm_button_clicked), NULL);
  g_signal_connect (G_OBJECT (about), "clicked",
                    G_CALLBACK (about_button_clicked), NULL);
  g_signal_connect (G_OBJECT (next_button), "clicked",
                    G_CALLBACK (connection_next_clicked), NULL);
  g_signal_connect (G_OBJECT (username_entry), "changed",
                    G_CALLBACK (username_changed_callback), NULL);
  g_signal_connect (G_OBJECT (password_entry), "changed",
                    G_CALLBACK (password_or_identity_changed_callback), NULL);
  g_signal_connect (G_OBJECT (identity_entry), "changed",
                    G_CALLBACK (password_or_identity_changed_callback), NULL);

  /* Call this signal to initialize the sensitivity of the sudo
   * button correctly.
   */
  username_changed_callback (NULL, NULL);
}

/**
 * If the username is "root", disable the sudo button.
 */
static void
username_changed_callback (GtkWidget *w, gpointer data)
{
  const char *str;
  int username_is_root;
  int sudo_is_set;

  str = gtk_entry_get_text (GTK_ENTRY (username_entry));
  username_is_root = str != NULL && STREQ (str, "root");
  sudo_is_set = gtk_toggle_button_get_active (GTK_TOGGLE_BUTTON (sudo_button));

  /* The sudo button is sensitive if:
   * - The username is not "root", or
   * - The button is not already checked (to allow the user to uncheck it)
   */
  gtk_widget_set_sensitive (sudo_button, !username_is_root || sudo_is_set);
}

/**
 * The password or SSH identity URL entries are mutually exclusive, so
 * if one contains text then disable the other.  This function is
 * called when the "changed" signal is received on either.
 */
static void
password_or_identity_changed_callback (GtkWidget *w, gpointer data)
{
  const char *str;
  int password_set;
  int identity_set;

  str = gtk_entry_get_text (GTK_ENTRY (password_entry));
  password_set = str != NULL && STRNEQ (str, "");
  str = gtk_entry_get_text (GTK_ENTRY (identity_entry));
  identity_set = str != NULL && STRNEQ (str, "");

  if (!password_set && !identity_set) {
    gtk_widget_set_sensitive (password_entry, TRUE);
    gtk_widget_set_sensitive (identity_entry, TRUE);
  }
  else if (identity_set)
    gtk_widget_set_sensitive (password_entry, FALSE);
  else if (password_set)
    gtk_widget_set_sensitive (identity_entry, FALSE);
}

/**
 * Hide all other dialogs and show the connection dialog.
 */
static void
show_connection_dialog (void)
{
  /* Hide the other dialogs. */
  gtk_widget_hide (conv_dlg);
  gtk_widget_hide (run_dlg);

  /* Show everything except the spinner. */
  gtk_widget_show_all (conn_dlg);
  gtk_widget_hide (spinner_hbox);
}

/**
 * Callback from the C<Test connection> button.
 *
 * This initiates a background thread which actually does the ssh to
 * the conversion server and the rest of the testing (see
 * C<test_connection_thread>).
 */
static void
test_connection_clicked (GtkWidget *w, gpointer data)
{
  struct config *config = data;
  const gchar *port_str;
  const gchar *identity_str;
  size_t errors = 0;
  struct config *copy;
  int err;
  pthread_t tid;
  pthread_attr_t attr;

  gtk_label_set_text (GTK_LABEL (spinner_message), "");
  gtk_widget_show_all (spinner_hbox);
#ifdef GTK_SPINNER
  gtk_widget_hide (spinner);
#endif

  /* Get the fields from the various widgets. */
  free (config->remote.server);
  config->remote.server = strdup (gtk_entry_get_text (GTK_ENTRY (server_entry)));
  if (STREQ (config->remote.server, "")) {
    gtk_label_set_text (GTK_LABEL (spinner_message),
                        _("error: No conversion server given."));
    gtk_widget_grab_focus (server_entry);
    errors++;
  }
  port_str = gtk_entry_get_text (GTK_ENTRY (port_entry));
  if (sscanf (port_str, "%d", &config->remote.port) != 1 ||
      config->remote.port <= 0 || config->remote.port >= 65536) {
    gtk_label_set_text (GTK_LABEL (spinner_message),
                        _("error: Invalid port number. If in doubt, use \"22\"."));
    gtk_widget_grab_focus (port_entry);
    errors++;
  }
  free (config->auth.username);
  config->auth.username = strdup (gtk_entry_get_text (GTK_ENTRY (username_entry)));
  if (STREQ (config->auth.username, "")) {
    gtk_label_set_text (GTK_LABEL (spinner_message),
                        _("error: No user name.  If in doubt, use \"root\"."));
    gtk_widget_grab_focus (username_entry);
    errors++;
  }
  free (config->auth.password);
  config->auth.password = strdup (gtk_entry_get_text (GTK_ENTRY (password_entry)));

  free (config->auth.identity.url);
  identity_str = gtk_entry_get_text (GTK_ENTRY (identity_entry));
  if (identity_str && STRNEQ (identity_str, ""))
    config->auth.identity.url = strdup (identity_str);
  else
    config->auth.identity.url = NULL;
  config->auth.identity.file_needs_update = 1;

  config->auth.sudo = gtk_toggle_button_get_active (GTK_TOGGLE_BUTTON (sudo_button));

  if (errors)
    return;

  /* Give the testing thread its own copy of the config in case we
   * update the config in the main thread.
   */
  copy = copy_config (config);

  /* No errors so far, so test the connection in a background thread. */
  pthread_attr_init (&attr);
  pthread_attr_setdetachstate (&attr, PTHREAD_CREATE_DETACHED);
  err = pthread_create (&tid, &attr, test_connection_thread, copy);
  if (err != 0)
    error (EXIT_FAILURE, err, "pthread_create");
  pthread_attr_destroy (&attr);
}

/**
 * Run C<test_connection> (in a detached background thread).  Once it
 * finishes stop the spinner and set the spinner message
 * appropriately.  If the test is successful then we enable the
 * C<Next> button.  If unsuccessful, an error is shown in the
 * connection dialog.
 */
static void *
test_connection_thread (void *data)
{
  struct config *copy = data;
  int r;

  g_idle_add (start_spinner, NULL);

  wait_network_online (copy);
  r = test_connection (copy);
  free_config (copy);

  g_idle_add (stop_spinner, NULL);

  if (r == -1)
    g_idle_add (test_connection_error, NULL);
  else
    g_idle_add (test_connection_ok, NULL);

  /* Thread is detached anyway, so no one is waiting for the status. */
  return NULL;
}

/**
 * Idle task called from C<test_connection_thread> (but run on the
 * main thread) to start the spinner in the connection dialog.
 */
static gboolean
start_spinner (gpointer user_data)
{
  gtk_label_set_text (GTK_LABEL (spinner_message),
                      _("Testing the connection to the conversion server ..."));
#ifdef GTK_SPINNER
  gtk_widget_show (spinner);
  gtk_spinner_start (GTK_SPINNER (spinner));
#endif
  return FALSE;
}

/**
 * Idle task called from C<test_connection_thread> (but run on the
 * main thread) to stop the spinner in the connection dialog.
 */
static gboolean
stop_spinner (gpointer user_data)
{
#ifdef GTK_SPINNER
  gtk_spinner_stop (GTK_SPINNER (spinner));
  gtk_widget_hide (spinner);
#endif
  return FALSE;
}

/**
 * Idle task called from C<test_connection_thread> (but run on the
 * main thread) when there is an error.  Display the error message and
 * disable the C<Next> button so the user is forced to correct it.
 */
static gboolean
test_connection_error (gpointer user_data)
{
  const char *err = get_ssh_error ();

  gtk_label_set_text (GTK_LABEL (spinner_message), err);
  /* Disable the Next button. */
  gtk_widget_set_sensitive (next_button, FALSE);

  return FALSE;
}

/**
 * Idle task called from C<test_connection_thread> (but run on the
 * main thread) when the connection test was successful.
 */
static gboolean
test_connection_ok (gpointer user_data)
{
  gtk_label_set_text
    (GTK_LABEL (spinner_message),
     _("Connected to the conversion server.\n"
       "Press the \"Next\" button to configure the conversion process."));

  /* Enable the Next button. */
  gtk_widget_set_sensitive (next_button, TRUE);
  gtk_widget_grab_focus (next_button);

  /* Update the information in the conversion dialog. */
  set_info_label ();

  return FALSE;
}

/**
 * Callback from the C<Configure network ...> button.  This dialog is
 * handled entirely by an external program which is part of
 * NetworkManager.
 */
static void
configure_network_button_clicked (GtkWidget *w, gpointer data)
{
  if (access ("/sbin/yast2", X_OK) >= 0)
    ignore_value (system ("yast2 lan &"));
  else
    ignore_value (system ("nm-connection-editor &"));
}

/**
 * Callback from the C<XTerm ...> button.
 */
static void
xterm_button_clicked (GtkWidget *w, gpointer data)
{
  ignore_value (system ("xterm &"));
}

/**
 * Callback from the C<About virt-p2v ...> button.
 *
 * See also F<p2v/about-authors.c> and F<p2v/about-license.c>.
 */
static void
about_button_clicked (GtkWidget *w, gpointer data)
{
  GtkWidget *dialog;
  GtkWidget *parent = conn_dlg;

  dialog = gtk_about_dialog_new ();

  g_object_set (G_OBJECT (dialog),
                "program-name", getprogname (),
                "version", PACKAGE_VERSION_FULL " (" host_cpu ")",
                "copyright", "\u00A9 2009-2019 Red Hat Inc.",
                "comments",
                  _("Virtualize a physical machine to run on KVM"),
#if GTK_CHECK_VERSION(3,0,0)   /* gtk >= 3 */
                "license-type", GTK_LICENSE_GPL_2_0,
#else
                "license", gplv2plus,
#endif
                "website", "http://libguestfs.org/",
                "authors", authors,
                NULL);

  if (documenters[0] != NULL)
    g_object_set (G_OBJECT (dialog),
                  "documenters", documenters,
                  NULL);

  if (qa[0] != NULL)
    gtk_about_dialog_add_credit_section (GTK_ABOUT_DIALOG (dialog),
                                         "Quality assurance", qa);

  if (others[0] != NULL)
    gtk_about_dialog_add_credit_section (GTK_ABOUT_DIALOG (dialog),
                                         "Libguestfs development", others);

  gtk_window_set_modal (GTK_WINDOW (dialog), TRUE);
  gtk_window_set_transient_for (GTK_WINDOW (dialog), GTK_WINDOW (parent));
  gtk_window_set_destroy_with_parent (GTK_WINDOW (dialog), TRUE);

  gtk_dialog_run (GTK_DIALOG (dialog));
  gtk_widget_destroy (dialog);
}

/**
 * Callback when the connection dialog C<Next> button has been
 * clicked.
 */
static void
connection_next_clicked (GtkWidget *w, gpointer data)
{
  /* Switch to the conversion dialog. */
  show_conversion_dialog ();
}

/*----------------------------------------------------------------------*/
/* Conversion dialog. */

static void populate_disks (GtkTreeView *disks_list);
static void populate_removable (GtkTreeView *removable_list);
static void populate_interfaces (GtkTreeView *interfaces_list);
static void toggled (GtkCellRendererToggle *cell, gchar *path_str, gpointer data);
static void network_edited_callback (GtkCellRendererToggle *cell, gchar *path_str, gchar *new_text, gpointer data);
static gboolean maybe_identify_click (GtkWidget *interfaces_list, GdkEventButton *event, gpointer data);
static void set_disks_from_ui (struct config *);
static void set_removable_from_ui (struct config *);
static void set_interfaces_from_ui (struct config *);
static void conversion_back_clicked (GtkWidget *w, gpointer data);
static void start_conversion_clicked (GtkWidget *w, gpointer data);
static void vcpus_or_memory_check_callback (GtkWidget *w, gpointer data);
static void notify_ui_callback (int type, const char *data);
static int get_vcpus_from_conv_dlg (void);
static uint64_t get_memory_from_conv_dlg (void);

enum {
  DISKS_COL_CONVERT = 0,
  DISKS_COL_DEVICE,
  NUM_DISKS_COLS,
};

enum {
  REMOVABLE_COL_CONVERT = 0,
  REMOVABLE_COL_DEVICE,
  NUM_REMOVABLE_COLS,
};

enum {
  INTERFACES_COL_CONVERT = 0,
  INTERFACES_COL_DEVICE,
  INTERFACES_COL_NETWORK,
  NUM_INTERFACES_COLS,
};

/**
 * Create the conversion dialog.
 *
 * This creates the dialog, but it is not displayed.  See
 * C<show_conversion_dialog>.
 */
static void
create_conversion_dialog (struct config *config)
{
  GtkWidget *back;
  GtkWidget *hbox, *left_vbox, *right_vbox;
  GtkWidget *target_frame, *target_vbox, *target_tbl;
  GtkWidget *guestname_label, *vcpus_label, *memory_label;
  GtkWidget *output_frame, *output_vbox, *output_tbl;
  GtkWidget *o_label, *oa_label, *oc_label, *of_label, *os_label;
  GtkWidget *info_frame;
  GtkWidget *disks_frame, *disks_sw;
  GtkWidget *removable_frame, *removable_sw;
  GtkWidget *interfaces_frame, *interfaces_sw;
  char vcpus_str[64];
  char memory_str[64];

  conv_dlg = gtk_dialog_new ();
  gtk_window_set_title (GTK_WINDOW (conv_dlg), getprogname ());
  gtk_window_set_resizable (GTK_WINDOW (conv_dlg), FALSE);
  /* XXX It would be nice not to have to set this explicitly, but
   * if we don't then Gtk chooses a very small window.
   */
  gtk_widget_set_size_request (conv_dlg, 900, 600);

  /* The main dialog area. */
  hbox_new (hbox, TRUE, 1);
  vbox_new (left_vbox, FALSE, 1);
  vbox_new (right_vbox, TRUE, 1);

  /* The left column: target properties and output options. */
  target_frame = gtk_frame_new (_("Target properties"));
  gtk_container_set_border_width (GTK_CONTAINER (target_frame), 4);

  vbox_new (target_vbox, FALSE, 1);

  table_new (target_tbl, 3, 3);
  guestname_label = gtk_label_new_with_mnemonic (_("_Name:"));
  table_attach (target_tbl, guestname_label,
                0, 1, 0, 1, GTK_FILL, GTK_FILL, 1, 1);
  set_alignment (guestname_label, 1., 0.5);
  guestname_entry = gtk_entry_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (guestname_label), guestname_entry);
  if (config->guestname != NULL)
    gtk_entry_set_text (GTK_ENTRY (guestname_entry), config->guestname);
  table_attach (target_tbl, guestname_entry,
                1, 2, 0, 1, GTK_FILL, GTK_FILL, 1, 1);

  vcpus_label = gtk_label_new_with_mnemonic (_("# _vCPUs:"));
  table_attach (target_tbl, vcpus_label,
                0, 1, 1, 2, GTK_FILL, GTK_FILL, 1, 1);
  set_alignment (vcpus_label, 1., 0.5);
  vcpus_entry = gtk_entry_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (vcpus_label), vcpus_entry);
  snprintf (vcpus_str, sizeof vcpus_str, "%d", config->vcpus);
  gtk_entry_set_text (GTK_ENTRY (vcpus_entry), vcpus_str);
  table_attach (target_tbl, vcpus_entry,
                1, 2, 1, 2, GTK_FILL, GTK_FILL, 1, 1);
  vcpus_warning = gtk_image_new_from_stock (GTK_STOCK_DIALOG_WARNING,
                                            GTK_ICON_SIZE_BUTTON);
  table_attach (target_tbl, vcpus_warning,
                2, 3, 1, 2, 0, 0, 1, 1);

  memory_label = gtk_label_new_with_mnemonic (_("_Memory (MB):"));
  table_attach (target_tbl, memory_label,
                0, 1, 2, 3, GTK_FILL, GTK_FILL, 1, 1);
  set_alignment (memory_label, 1., 0.5);
  memory_entry = gtk_entry_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (memory_label), memory_entry);
  snprintf (memory_str, sizeof memory_str, "%" PRIu64,
            config->memory / 1024 / 1024);
  gtk_entry_set_text (GTK_ENTRY (memory_entry), memory_str);
  table_attach (target_tbl, memory_entry,
                1, 2, 2, 3, GTK_FILL, GTK_FILL, 1, 1);
  memory_warning = gtk_image_new_from_stock (GTK_STOCK_DIALOG_WARNING,
                                             GTK_ICON_SIZE_BUTTON);
  table_attach (target_tbl, memory_warning,
                2, 3, 2, 3, 0, 0, 1, 1);

  gtk_box_pack_start (GTK_BOX (target_vbox), target_tbl, TRUE, TRUE, 0);

  target_warning_label = gtk_label_new ("");
  gtk_label_set_line_wrap (GTK_LABEL (target_warning_label), TRUE);
  gtk_label_set_line_wrap_mode (GTK_LABEL (target_warning_label),
                                PANGO_WRAP_WORD);
  gtk_widget_set_size_request (target_warning_label, -1, 7 * 16);
  gtk_box_pack_end (GTK_BOX (target_vbox), target_warning_label, TRUE, TRUE, 0);

  gtk_container_add (GTK_CONTAINER (target_frame), target_vbox);

  output_frame = gtk_frame_new (_("Virt-v2v output options"));
  gtk_container_set_border_width (GTK_CONTAINER (output_frame), 4);

  vbox_new (output_vbox, FALSE, 1);

  table_new (output_tbl, 5, 2);
  o_label = gtk_label_new_with_mnemonic (_("Output _to (-o):"));
  table_attach (output_tbl, o_label,
                0, 1, 0, 1, GTK_FILL, GTK_FILL, 1, 1);
  set_alignment (o_label, 1., 0.5);
  o_combo = gtk_combo_box_text_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (o_label), o_combo);
  gtk_widget_set_tooltip_markup (o_combo, _("<b>libvirt</b> means send the converted guest to libvirt-managed KVM on the conversion server.  <b>local</b> means put it in a directory on the conversion server.  <b>rhv</b> means write it to RHV-M/oVirt.  <b>glance</b> means write it to OpenStack Glance.  See the virt-v2v(1) manual page for more information about output options."));
  repopulate_output_combo (config);
  table_attach (output_tbl, o_combo,
                1, 2, 0, 1, GTK_FILL, GTK_FILL, 1, 1);

  oc_label = gtk_label_new_with_mnemonic (_("_Output conn. (-oc):"));
  table_attach (output_tbl, oc_label,
                0, 1, 1, 2, GTK_FILL, GTK_FILL, 1, 1);
  set_alignment (oc_label, 1., 0.5);
  oc_entry = gtk_entry_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (oc_label), oc_entry);
  gtk_widget_set_tooltip_markup (oc_entry, _("For <b>libvirt</b> only, the libvirt connection URI, or leave blank to add the guest to the default libvirt instance on the conversion server.  For others, leave this field blank."));
  if (config->output.connection != NULL)
    gtk_entry_set_text (GTK_ENTRY (oc_entry), config->output.connection);
  table_attach (output_tbl, oc_entry,
                1, 2, 1, 2, GTK_FILL, GTK_FILL, 1, 1);

  os_label = gtk_label_new_with_mnemonic (_("Output _storage (-os):"));
  table_attach (output_tbl, os_label,
                0, 1, 2, 3, GTK_FILL, GTK_FILL, 1, 1);
  set_alignment (os_label, 1., 0.5);
  os_entry = gtk_entry_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (os_label), os_entry);
  gtk_widget_set_tooltip_markup (os_entry, _("For <b>local</b>, put the directory name on the conversion server.  For <b>rhv</b>, put the Export Storage Domain (server:/mountpoint).  For others, leave this field blank."));
  if (config->output.storage != NULL)
    gtk_entry_set_text (GTK_ENTRY (os_entry), config->output.storage);
  table_attach (output_tbl, os_entry,
                1, 2, 2, 3, GTK_FILL, GTK_FILL, 1, 1);

  of_label = gtk_label_new_with_mnemonic (_("Output _format (-of):"));
  table_attach (output_tbl, of_label,
                0, 1, 3, 4, GTK_FILL, GTK_FILL, 1, 1);
  set_alignment (of_label, 1., 0.5);
  of_entry = gtk_entry_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (of_label), of_entry);
  gtk_widget_set_tooltip_markup (of_entry, _("The output disk format, typically <b>raw</b> or <b>qcow2</b>.  If blank, defaults to <b>raw</b>."));
  if (config->output.format != NULL)
    gtk_entry_set_text (GTK_ENTRY (of_entry), config->output.format);
  table_attach (output_tbl, of_entry,
                1, 2, 3, 4, GTK_FILL, GTK_FILL, 1, 1);

  oa_label = gtk_label_new_with_mnemonic (_("Output _allocation (-oa):"));
  table_attach (output_tbl, oa_label,
                0, 1, 4, 5, GTK_FILL, GTK_FILL, 1, 1);
  set_alignment (oa_label, 1., 0.5);
  oa_combo = gtk_combo_box_text_new ();
  gtk_label_set_mnemonic_widget (GTK_LABEL (oa_label), oa_combo);
  gtk_combo_box_text_append_text (GTK_COMBO_BOX_TEXT (oa_combo),
                                  "sparse");
  gtk_combo_box_text_append_text (GTK_COMBO_BOX_TEXT (oa_combo),
                                  "preallocated");
  switch (config->output.allocation) {
  case OUTPUT_ALLOCATION_PREALLOCATED:
    gtk_combo_box_set_active (GTK_COMBO_BOX (oa_combo), 1);
    break;
  default:
    gtk_combo_box_set_active (GTK_COMBO_BOX (oa_combo), 0);
    break;
  }
  table_attach (output_tbl, oa_combo,
                1, 2, 4, 5, GTK_FILL, GTK_FILL, 1, 1);

  gtk_box_pack_start (GTK_BOX (output_vbox), output_tbl, TRUE, TRUE, 0);
  gtk_container_add (GTK_CONTAINER (output_frame), output_vbox);

  info_frame = gtk_frame_new (_("Information"));
  gtk_container_set_border_width (GTK_CONTAINER (info_frame), 4);
  info_label = gtk_label_new (NULL);
  set_alignment (info_label, 0.1, 0.5);
  set_info_label ();
  gtk_container_add (GTK_CONTAINER (info_frame), info_label);

  /* The right column: select devices to be converted. */
  disks_frame = gtk_frame_new (_("Fixed hard disks"));
  gtk_container_set_border_width (GTK_CONTAINER (disks_frame), 4);
  disks_sw = gtk_scrolled_window_new (NULL, NULL);
  gtk_container_set_border_width (GTK_CONTAINER (disks_sw), 8);
  gtk_scrolled_window_set_policy (GTK_SCROLLED_WINDOW (disks_sw),
                                  GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  disks_list = gtk_tree_view_new ();
  populate_disks (GTK_TREE_VIEW (disks_list));
  scrolled_window_add_with_viewport (disks_sw, disks_list);
  gtk_container_add (GTK_CONTAINER (disks_frame), disks_sw);

  removable_frame = gtk_frame_new (_("Removable media"));
  gtk_container_set_border_width (GTK_CONTAINER (removable_frame), 4);
  removable_sw = gtk_scrolled_window_new (NULL, NULL);
  gtk_container_set_border_width (GTK_CONTAINER (removable_sw), 8);
  gtk_scrolled_window_set_policy (GTK_SCROLLED_WINDOW (removable_sw),
                                  GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  removable_list = gtk_tree_view_new ();
  populate_removable (GTK_TREE_VIEW (removable_list));
  scrolled_window_add_with_viewport (removable_sw,  removable_list);
  gtk_container_add (GTK_CONTAINER (removable_frame), removable_sw);

  interfaces_frame = gtk_frame_new (_("Network interfaces"));
  gtk_container_set_border_width (GTK_CONTAINER (interfaces_frame), 4);
  interfaces_sw = gtk_scrolled_window_new (NULL, NULL);
  gtk_container_set_border_width (GTK_CONTAINER (interfaces_sw), 8);
  gtk_scrolled_window_set_policy (GTK_SCROLLED_WINDOW (interfaces_sw),
                                  GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  interfaces_list = gtk_tree_view_new ();
  /* See maybe_identify_click below for what we're doing. */
  g_signal_connect (interfaces_list, "button-press-event",
                    G_CALLBACK (maybe_identify_click), NULL);
  gtk_widget_set_tooltip_markup (interfaces_list, _("Left click on an interface name to flash the light on the physical interface."));
  populate_interfaces (GTK_TREE_VIEW (interfaces_list));
  scrolled_window_add_with_viewport (interfaces_sw, interfaces_list);
  gtk_container_add (GTK_CONTAINER (interfaces_frame), interfaces_sw);

  /* Pack the top level dialog. */
  gtk_box_pack_start (GTK_BOX (left_vbox), target_frame, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (left_vbox), output_frame, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (left_vbox), info_frame, TRUE, TRUE, 0);

  gtk_box_pack_start (GTK_BOX (right_vbox), disks_frame, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (right_vbox), removable_frame, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (right_vbox), interfaces_frame, TRUE, TRUE, 0);

  gtk_box_pack_start (GTK_BOX (hbox), left_vbox, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (hbox), right_vbox, TRUE, TRUE, 0);
  gtk_box_pack_start
    (GTK_BOX (gtk_dialog_get_content_area (GTK_DIALOG (conv_dlg))),
     hbox, TRUE, TRUE, 0);

  /* Buttons. */
  gtk_dialog_add_buttons (GTK_DIALOG (conv_dlg),
                          _("_Back"), 1,
                          _("Start _conversion"), 2,
                          NULL);
  back = gtk_dialog_get_widget_for_response (GTK_DIALOG (conv_dlg), 1);
  start_button = gtk_dialog_get_widget_for_response (GTK_DIALOG (conv_dlg), 2);

  /* Signals. */
  g_signal_connect_swapped (G_OBJECT (conv_dlg), "destroy",
                            G_CALLBACK (gtk_main_quit), NULL);
  g_signal_connect (G_OBJECT (back), "clicked",
                    G_CALLBACK (conversion_back_clicked), NULL);
  g_signal_connect (G_OBJECT (start_button), "clicked",
                    G_CALLBACK (start_conversion_clicked), config);
  g_signal_connect (G_OBJECT (vcpus_entry), "changed",
                    G_CALLBACK (vcpus_or_memory_check_callback), NULL);
  g_signal_connect (G_OBJECT (memory_entry), "changed",
                    G_CALLBACK (vcpus_or_memory_check_callback), NULL);
}

/**
 * Hide all other dialogs and show the conversion dialog.
 */
static void
show_conversion_dialog (void)
{
  /* Hide the other dialogs. */
  gtk_widget_hide (conn_dlg);
  gtk_widget_hide (run_dlg);

  /* Show the conversion dialog. */
  gtk_widget_show_all (conv_dlg);
  gtk_widget_hide (vcpus_warning);
  gtk_widget_hide (memory_warning);

  /* output_drivers may have been updated, so repopulate o_combo. */
  repopulate_output_combo (NULL);
}

/**
 * Update the C<Information> section in the conversion dialog.
 *
 * Note that C<v2v_version> (the remote virt-v2v version) is read from
 * the remote virt-v2v in the C<test_connection> function.
 */
static void
set_info_label (void)
{
  CLEANUP_FREE char *text;
  int r;

  if (!v2v_version)
    r = asprintf (&text, _("virt-p2v (client):\n%s"), PACKAGE_VERSION);
  else
    r = asprintf (&text,
                  _("virt-p2v (client):\n"
                    "%s\n"
                    "virt-v2v (conversion server):\n"
                    "%s"),
                  PACKAGE_VERSION_FULL, v2v_version);
  if (r == -1) {
    perror ("asprintf");
    return;
  }

  gtk_label_set_text (GTK_LABEL (info_label), text);
}

/**
 * Repopulate the list of output drivers in the C<Output to (-o)>
 * combo.  The list of drivers is read from the remote virt-v2v
 * instance in C<test_connection>.
 */
static void
repopulate_output_combo (struct config *config)
{
  GtkTreeModel *model;
  CLEANUP_FREE char *output;
  size_t i;

  /* Which driver is currently selected? */
  if (config && config->output.type)
    output = strdup (config->output.type);
  else
    output = gtk_combo_box_text_get_active_text (GTK_COMBO_BOX_TEXT (o_combo));

  /* Remove existing rows in o_combo. */
  model = gtk_combo_box_get_model (GTK_COMBO_BOX (o_combo));
  gtk_list_store_clear (GTK_LIST_STORE (model));

  /* List of output_drivers from virt-v2v not read yet, so present
   * a standard set of drivers.
   */
  if (output_drivers == NULL) {
    gtk_combo_box_text_append_text (GTK_COMBO_BOX_TEXT (o_combo), "libvirt");
    gtk_combo_box_text_append_text (GTK_COMBO_BOX_TEXT (o_combo), "local");
    /* Use rhev instead of rhv here so we can work with old virt-v2v. */
    gtk_combo_box_text_append_text (GTK_COMBO_BOX_TEXT (o_combo), "rhev");
    if (output == NULL || STREQ (output, "libvirt"))
      gtk_combo_box_set_active (GTK_COMBO_BOX (o_combo), 0);
    else if (STREQ (output, "local"))
      gtk_combo_box_set_active (GTK_COMBO_BOX (o_combo), 1);
    else if (STREQ (output, "rhev"))
      gtk_combo_box_set_active (GTK_COMBO_BOX (o_combo), 2);
  }
  /* List of -o options read from remote virt-v2v --machine-readable. */
  else {
    for (i = 0; output_drivers[i] != NULL; ++i)
      gtk_combo_box_text_append_text (GTK_COMBO_BOX_TEXT (o_combo),
                                      output_drivers[i]);
    if (output) {
      for (i = 0; output_drivers[i] != NULL; ++i)
        if (STREQ (output, output_drivers[i]))
          gtk_combo_box_set_active (GTK_COMBO_BOX (o_combo), i);
    }
    else
      gtk_combo_box_set_active (GTK_COMBO_BOX (o_combo), 0);
  }
}

/**
 * Populate the C<Fixed hard disks> treeview.
 */
static void
populate_disks (GtkTreeView *disks_list)
{
  GtkListStore *disks_store;
  GtkCellRenderer *disks_col_convert, *disks_col_device;
  GtkTreeIter iter;
  size_t i;

  disks_store = gtk_list_store_new (NUM_DISKS_COLS,
                                    G_TYPE_BOOLEAN, G_TYPE_STRING);
  if (all_disks != NULL) {
    for (i = 0; all_disks[i] != NULL; ++i) {
      uint64_t size;
      CLEANUP_FREE char *size_gb = NULL;
      CLEANUP_FREE char *model = NULL;
      CLEANUP_FREE char *serial = NULL;
      CLEANUP_FREE char *device_descr = NULL;

      if (all_disks[i][0] != '/') { /* not using --test-disk */
        size = get_blockdev_size (all_disks[i]);
        if (asprintf (&size_gb, "%" PRIu64 "G", size) == -1)
          error (EXIT_FAILURE, errno, "asprintf");
        model = get_blockdev_model (all_disks[i]);
        serial = get_blockdev_serial (all_disks[i]);
      }

      if (asprintf (&device_descr,
                    "<b>%s</b>\n"
                    "<small>"
                    "%s %s\n"
                    "%s%s"
                    "</small>",
                    all_disks[i],
                    size_gb ? size_gb : "", model ? model : "",
                    serial ? "s/n " : "", serial ? serial : "") == -1)
        error (EXIT_FAILURE, errno, "asprintf");

      gtk_list_store_append (disks_store, &iter);
      gtk_list_store_set (disks_store, &iter,
                          DISKS_COL_CONVERT, TRUE,
                          DISKS_COL_DEVICE, device_descr,
                          -1);
    }
  }
  gtk_tree_view_set_model (disks_list,
                           GTK_TREE_MODEL (disks_store));
  gtk_tree_view_set_headers_visible (disks_list, TRUE);
  disks_col_convert = gtk_cell_renderer_toggle_new ();
  gtk_tree_view_insert_column_with_attributes (disks_list,
                                               -1,
                                               _("Convert"),
                                               disks_col_convert,
                                               "active", DISKS_COL_CONVERT,
                                               NULL);
  gtk_cell_renderer_set_alignment (disks_col_convert, 0.5, 0.0);
  disks_col_device = gtk_cell_renderer_text_new ();
  gtk_tree_view_insert_column_with_attributes (disks_list,
                                               -1,
                                               _("Device"),
                                               disks_col_device,
                                               "markup", DISKS_COL_DEVICE,
                                               NULL);
  gtk_cell_renderer_set_alignment (disks_col_device, 0.0, 0.0);

  g_signal_connect (disks_col_convert, "toggled",
                    G_CALLBACK (toggled), disks_store);
}

/**
 * Populate the C<Removable media> treeview.
 */
static void
populate_removable (GtkTreeView *removable_list)
{
  GtkListStore *removable_store;
  GtkCellRenderer *removable_col_convert, *removable_col_device;
  GtkTreeIter iter;
  size_t i;

  removable_store = gtk_list_store_new (NUM_REMOVABLE_COLS,
                                        G_TYPE_BOOLEAN, G_TYPE_STRING);
  if (all_removable != NULL) {
    for (i = 0; all_removable[i] != NULL; ++i) {
      CLEANUP_FREE char *device_descr = NULL;

      if (asprintf (&device_descr, "<b>%s</b>\n", all_removable[i]) == -1)
        error (EXIT_FAILURE, errno, "asprintf");

      gtk_list_store_append (removable_store, &iter);
      gtk_list_store_set (removable_store, &iter,
                          REMOVABLE_COL_CONVERT, TRUE,
                          REMOVABLE_COL_DEVICE, device_descr,
                          -1);
    }
  }
  gtk_tree_view_set_model (removable_list,
                           GTK_TREE_MODEL (removable_store));
  gtk_tree_view_set_headers_visible (removable_list, TRUE);
  removable_col_convert = gtk_cell_renderer_toggle_new ();
  gtk_tree_view_insert_column_with_attributes (removable_list,
                                               -1,
                                               _("Convert"),
                                               removable_col_convert,
                                               "active", REMOVABLE_COL_CONVERT,
                                               NULL);
  gtk_cell_renderer_set_alignment (removable_col_convert, 0.5, 0.0);
  removable_col_device = gtk_cell_renderer_text_new ();
  gtk_tree_view_insert_column_with_attributes (removable_list,
                                               -1,
                                               _("Device"),
                                               removable_col_device,
                                               "markup", REMOVABLE_COL_DEVICE,
                                               NULL);
  gtk_cell_renderer_set_alignment (removable_col_device, 0.0, 0.0);

  g_signal_connect (removable_col_convert, "toggled",
                    G_CALLBACK (toggled), removable_store);
}

/**
 * Populate the C<Network interfaces> treeview.
 */
static void
populate_interfaces (GtkTreeView *interfaces_list)
{
  GtkListStore *interfaces_store;
  GtkCellRenderer *interfaces_col_convert, *interfaces_col_device,
    *interfaces_col_network;
  GtkTreeIter iter;
  size_t i;

  interfaces_store = gtk_list_store_new (NUM_INTERFACES_COLS,
                                         G_TYPE_BOOLEAN, G_TYPE_STRING,
                                         G_TYPE_STRING);
  if (all_interfaces) {
    for (i = 0; all_interfaces[i] != NULL; ++i) {
      const char *if_name = all_interfaces[i];
      CLEANUP_FREE char *device_descr = NULL;
      CLEANUP_FREE char *if_addr = get_if_addr (if_name);
      CLEANUP_FREE char *if_vendor = get_if_vendor (if_name, 40);

      if (asprintf (&device_descr,
                    "<b>%s</b>\n"
                    "<small>"
                    "%s\n"
                    "%s"
                    "</small>\n"
                    "<small><u><span foreground=\"blue\">Identify interface</span></u></small>",
                    if_name,
                    if_addr ? : _("Unknown"),
                    if_vendor ? : _("Unknown")) == -1)
        error (EXIT_FAILURE, errno, "asprintf");

      gtk_list_store_append (interfaces_store, &iter);
      gtk_list_store_set (interfaces_store, &iter,
                          /* Only convert the first interface.  As
                           * they are sorted, this is usually the
                           * physical interface.
                           */
                          INTERFACES_COL_CONVERT, i == 0,
                          INTERFACES_COL_DEVICE, device_descr,
                          INTERFACES_COL_NETWORK, "default",
                          -1);
    }
  }
  gtk_tree_view_set_model (interfaces_list,
                           GTK_TREE_MODEL (interfaces_store));
  gtk_tree_view_set_headers_visible (interfaces_list, TRUE);
  interfaces_col_convert = gtk_cell_renderer_toggle_new ();
  gtk_tree_view_insert_column_with_attributes (interfaces_list,
                                               -1,
                                               _("Convert"),
                                               interfaces_col_convert,
                                               "active", INTERFACES_COL_CONVERT,
                                               NULL);
  gtk_cell_renderer_set_alignment (interfaces_col_convert, 0.5, 0.0);
  interfaces_col_device = gtk_cell_renderer_text_new ();
  gtk_tree_view_insert_column_with_attributes (interfaces_list,
                                               -1,
                                               _("Device"),
                                               interfaces_col_device,
                                               "markup", INTERFACES_COL_DEVICE,
                                               NULL);
  gtk_cell_renderer_set_alignment (interfaces_col_device, 0.0, 0.0);
  interfaces_col_network = gtk_cell_renderer_text_new ();
  gtk_tree_view_insert_column_with_attributes (interfaces_list,
                                               -1,
                                               _("Connect to virtual network"),
                                               interfaces_col_network,
                                               "text", INTERFACES_COL_NETWORK,
                                               NULL);
  gtk_cell_renderer_set_alignment (interfaces_col_network, 0.0, 0.0);

  g_signal_connect (interfaces_col_convert, "toggled",
                    G_CALLBACK (toggled), interfaces_store);

  g_object_set (interfaces_col_network, "editable", TRUE, NULL);
  g_signal_connect (interfaces_col_network, "edited",
                    G_CALLBACK (network_edited_callback), interfaces_store);
}

static void
toggled (GtkCellRendererToggle *cell, gchar *path_str, gpointer data)
{
  GtkTreeModel *model = data;
  GtkTreePath *path = gtk_tree_path_new_from_string (path_str);
  GtkTreeIter iter;
  gboolean v;

  gtk_tree_model_get_iter (model, &iter, path);
  gtk_tree_model_get (model, &iter, 0 /* CONVERT */, &v, -1);
  v ^= 1;
  gtk_list_store_set (GTK_LIST_STORE (model), &iter, 0 /* CONVERT */, v, -1);
  gtk_tree_path_free (path);
}

static void
network_edited_callback (GtkCellRendererToggle *cell, gchar *path_str,
                         gchar *new_text, gpointer data)
{
  GtkTreeModel *model = data;
  GtkTreePath *path;
  GtkTreeIter iter;

  if (new_text == NULL || STREQ (new_text, ""))
    return;

  path = gtk_tree_path_new_from_string (path_str);

  gtk_tree_model_get_iter (model, &iter, path);
  gtk_list_store_set (GTK_LIST_STORE (model), &iter,
                      INTERFACES_COL_NETWORK, new_text, -1);
  gtk_tree_path_free (path);
}

/**
 * When the user clicks on the interface name on the list of
 * interfaces, we want to run C<ethtool --identify>, which usually
 * makes some lights flash on the physical interface.
 *
 * We cannot catch clicks on the cell itself, so we have to go via a
 * more obscure route.  See L<http://stackoverflow.com/a/27207433> and
 * L<https://en.wikibooks.org/wiki/GTK%2B_By_Example/Tree_View/Events>
 */
static gboolean
maybe_identify_click (GtkWidget *interfaces_list, GdkEventButton *event,
                      gpointer data)
{
  gboolean ret = FALSE;         /* Did we handle this event? */
  guint button;

  /* Single left click only. */
  if (gdk_event_get_event_type ((const GdkEvent *) event) == GDK_BUTTON_PRESS &&
      gdk_event_get_button ((const GdkEvent *) event, &button) &&
      button == 1) {
    GtkTreePath *path;
    GtkTreeViewColumn *column;
    gdouble event_x, event_y;

    if (gdk_event_get_coords ((const GdkEvent *) event, &event_x, &event_y)
        && gtk_tree_view_get_path_at_pos (GTK_TREE_VIEW (interfaces_list),
                                          event_x, event_y,
                                          &path, &column, NULL, NULL)) {
      GList *cols;
      gint column_index;

      /* Get column index. */
      cols = gtk_tree_view_get_columns (GTK_TREE_VIEW (interfaces_list));
      column_index = g_list_index (cols, (gpointer) column);
      g_list_free (cols);

      if (column_index == INTERFACES_COL_DEVICE) {
        const gint *indices;
        gint row_index;
        const char *if_name;
        char *cmd;

        /* Get the row index. */
        indices = gtk_tree_path_get_indices (path);
        row_index = indices[0];

        /* And the interface name. */
        if_name = all_interfaces[row_index];

        /* Issue the ethtool command in the background. */
        if (asprintf (&cmd, "ethtool --identify '%s' 10 &", if_name) == -1)
          error (EXIT_FAILURE, errno, "asprintf");
        printf ("%s\n", cmd);
        ignore_value (system (cmd));

        free (cmd);

        ret = TRUE;             /* We handled this event. */
      }

      gtk_tree_path_free (path);
    }
  }

  return ret;
}

static void
set_from_ui_generic (char **all, char ***ret, GtkTreeView *list)
{
  GtkTreeModel *model;
  GtkTreeIter iter;
  gboolean b, v;
  size_t i, j;

  if (all == NULL) {
    guestfs_int_free_string_list (*ret);
    *ret = NULL;
    return;
  }

  model = gtk_tree_view_get_model (list);

  guestfs_int_free_string_list (*ret);
  *ret = malloc ((1 + guestfs_int_count_strings (all)) * sizeof (char *));
  if (*ret == NULL)
    error (EXIT_FAILURE, errno, "malloc");
  i = j = 0;

  b = gtk_tree_model_get_iter_first (model, &iter);
  while (b) {
    gtk_tree_model_get (model, &iter, 0 /* CONVERT */, &v, -1);
    if (v) {
      assert (all[i] != NULL);
      (*ret)[j++] = strdup (all[i]);
    }
    b = gtk_tree_model_iter_next (model, &iter);
    ++i;
  }

  (*ret)[j] = NULL;
}

static void
set_disks_from_ui (struct config *config)
{
  set_from_ui_generic (all_disks, &config->disks,
                       GTK_TREE_VIEW (disks_list));
}

static void
set_removable_from_ui (struct config *config)
{
  set_from_ui_generic (all_removable, &config->removable,
                       GTK_TREE_VIEW (removable_list));
}

static void
set_interfaces_from_ui (struct config *config)
{
  set_from_ui_generic (all_interfaces, &config->interfaces,
                       GTK_TREE_VIEW (interfaces_list));
}

static void
set_network_map_from_ui (struct config *config)
{
  GtkTreeView *list;
  GtkTreeModel *model;
  GtkTreeIter iter;
  gboolean b;
  const char *s;
  size_t i, j;

  if (all_interfaces == NULL) {
    guestfs_int_free_string_list (config->network_map);
    config->network_map = NULL;
    return;
  }

  list = GTK_TREE_VIEW (interfaces_list);
  model = gtk_tree_view_get_model (list);

  guestfs_int_free_string_list (config->network_map);
  config->network_map =
    malloc ((1 + guestfs_int_count_strings (all_interfaces))
            * sizeof (char *));
  if (config->network_map == NULL)
    error (EXIT_FAILURE, errno, "malloc");
  i = j = 0;

  b = gtk_tree_model_get_iter_first (model, &iter);
  while (b) {
    gtk_tree_model_get (model, &iter, INTERFACES_COL_NETWORK, &s, -1);
    if (s) {
      assert (all_interfaces[i] != NULL);
      if (asprintf (&config->network_map[j], "%s:%s",
                    all_interfaces[i], s) == -1)
        error (EXIT_FAILURE, errno, "asprintf");
      ++j;
    }
    b = gtk_tree_model_iter_next (model, &iter);
    ++i;
  }

  config->network_map[j] = NULL;
}

/**
 * The conversion dialog C<Back> button has been clicked.
 */
static void
conversion_back_clicked (GtkWidget *w, gpointer data)
{
  /* Switch to the connection dialog. */
  show_connection_dialog ();

  /* Better disable the Next button so the user is forced to
   * do "Test connection" again.
   */
  gtk_widget_set_sensitive (next_button, FALSE);
}

static char *concat_warning (char *warning, const char *fs, ...)
  __attribute__((format (printf,2,3)));

static char *
concat_warning (char *warning, const char *fs, ...)
{
  va_list args;
  char *msg;
  size_t len, len2;
  int r;

  if (warning == NULL) {
    warning = strdup ("");
    if (warning == NULL)
    malloc_fail:
      error (EXIT_FAILURE, errno, "malloc");
  }

  len = strlen (warning);
  if (len > 0 && warning[len-1] != '\n' && fs[0] != '\n') {
    warning = concat_warning (warning, "\n");
    len = strlen (warning);
  }

  va_start (args, fs);
  r = vasprintf (&msg, fs, args);
  va_end (args);
  if (r == -1) goto malloc_fail;

  len2 = strlen (msg);
  warning = realloc (warning, len + len2 + 1);
  if (warning == NULL) goto malloc_fail;
  memcpy (&warning[len], msg, len2 + 1);
  free (msg);

  return warning;
}

/**
 * Display a warning if the vCPUs or memory is outside the supported
 * range (L<https://bugzilla.redhat.com/823758>).
 */
static void
vcpus_or_memory_check_callback (GtkWidget *w, gpointer data)
{
  int vcpus;
  uint64_t memory;
  CLEANUP_FREE char *warning = NULL;

  vcpus = get_vcpus_from_conv_dlg ();
  memory = get_memory_from_conv_dlg ();

  if (vcpus > MAX_SUPPORTED_VCPUS) {
    gtk_widget_show (vcpus_warning);

    warning = concat_warning (warning,
                              _("Number of virtual CPUs is larger than what is supported for KVM (max: %d)."),
                              MAX_SUPPORTED_VCPUS);
  }
  else
    gtk_widget_hide (vcpus_warning);

  if (memory > MAX_SUPPORTED_MEMORY_MB * 1024 * 1024) {
    gtk_widget_show (memory_warning);

    warning = concat_warning (warning,
                              _("Memory size is larger than what is supported for KVM (max: %" PRIu64 ")."),
                              MAX_SUPPORTED_MEMORY_MB);
  }
  else
    gtk_widget_hide (memory_warning);

  if (warning != NULL) {
    warning = concat_warning (warning,
                              _("If you ignore this warning, conversion can still succeed, but the guest may not work or may not be supported on the target."));
    gtk_label_set_text (GTK_LABEL (target_warning_label), warning);
  }
  else
    gtk_label_set_text (GTK_LABEL (target_warning_label), "");
}

static int
get_vcpus_from_conv_dlg (void)
{
  const char *str;
  int i;

  str = gtk_entry_get_text (GTK_ENTRY (vcpus_entry));
  if (sscanf (str, "%d", &i) == 1 && i > 0)
    return i;
  else
    return 1;
}

static uint64_t
get_memory_from_conv_dlg (void)
{
  const char *str;
  uint64_t i;

  str = gtk_entry_get_text (GTK_ENTRY (memory_entry));
  if (sscanf (str, "%" SCNu64, &i) == 1 && i >= 256)
    return i * 1024 * 1024;
  else
    return UINT64_C (1024) * 1024 * 1024;
}

/*----------------------------------------------------------------------*/
/* Running dialog. */

static gboolean set_log_dir (gpointer remote_dir);
static gboolean set_status (gpointer msg);
static gboolean add_v2v_output (gpointer msg);
static void *start_conversion_thread (void *data);
static gboolean conversion_error (gpointer user_data);
static gboolean conversion_finished (gpointer user_data);
static void cancel_conversion_dialog (GtkWidget *w, gpointer data);
#ifdef USE_POPOVERS
static void activate_action (GSimpleAction *action, GVariant *parameter, gpointer user_data);
#else
static void shutdown_button_clicked (GtkToolButton *w, gpointer data);
#endif
static void shutdown_clicked (GtkWidget *w, gpointer data);
static void reboot_clicked (GtkWidget *w, gpointer data);
static gboolean close_running_dialog (GtkWidget *w, GdkEvent *event, gpointer data);

#ifdef USE_POPOVERS
static const GActionEntry shutdown_actions[] = {
  { "shutdown", activate_action, NULL, NULL, NULL },
  { "reboot", activate_action, NULL, NULL, NULL },
};
#endif

/**
 * Create the running dialog.
 *
 * This creates the dialog, but it is not displayed.  See
 * C<show_running_dialog>.
 */
static void
create_running_dialog (void)
{
  size_t i;
  static const char *tags[16] =
    { "black", "maroon", "green", "olive", "navy", "purple", "teal", "silver",
      "gray", "red", "lime", "yellow", "blue", "fuchsia", "cyan", "white" };
  GtkTextBuffer *buf;
#ifdef USE_POPOVERS
  GMenu *shutdown_menu;
  GSimpleActionGroup *shutdown_group;
#else
  GtkWidget *shutdown_menu;
  GtkWidget *shutdown_menu_item;
  GtkWidget *reboot_menu_item;
#endif

  run_dlg = gtk_dialog_new ();
  gtk_window_set_title (GTK_WINDOW (run_dlg), getprogname ());
  gtk_window_set_resizable (GTK_WINDOW (run_dlg), FALSE);

  /* The main dialog area. */
  v2v_output_sw = gtk_scrolled_window_new (NULL, NULL);
  gtk_scrolled_window_set_policy (GTK_SCROLLED_WINDOW (v2v_output_sw),
                                  GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  gtk_widget_set_size_request (v2v_output_sw, 700, 400);

  v2v_output = gtk_text_view_new ();
  gtk_text_view_set_editable (GTK_TEXT_VIEW (v2v_output), FALSE);
  gtk_text_view_set_wrap_mode (GTK_TEXT_VIEW (v2v_output), GTK_WRAP_CHAR);

  buf = gtk_text_view_get_buffer (GTK_TEXT_VIEW (v2v_output));
  for (i = 0; i < 16; ++i) {
    CLEANUP_FREE char *tag_name;

    if (asprintf (&tag_name, "tag_%s", tags[i]) == -1)
      error (EXIT_FAILURE, errno, "asprintf");
    v2v_output_tags[i] =
      gtk_text_buffer_create_tag (buf, tag_name, "foreground", tags[i], NULL);
  }

#if GTK_CHECK_VERSION(3,16,0)   /* gtk >= 3.16 */
  /* XXX This only sets the "CSS" style.  It's not clear how to set
   * the particular font.  However (by accident) this does at least
   * set the widget to use a monospace font.
   */
  GtkStyleContext *context = gtk_widget_get_style_context (v2v_output);
  gtk_style_context_add_class (context, "monospace");
#else
  PangoFontDescription *font;
  font = pango_font_description_from_string ("Monospace 11");
#if GTK_CHECK_VERSION(3,0,0)	/* gtk >= 3 */
  gtk_widget_override_font (v2v_output, font);
#else
  gtk_widget_modify_font (v2v_output, font);
#endif
  pango_font_description_free (font);
#endif

  log_label = gtk_label_new (NULL);
  set_alignment (log_label, 0., 0.5);
  set_padding (log_label, 10, 10);
  set_log_dir (NULL);
  status_label = gtk_label_new (NULL);
  set_alignment (status_label, 0., 0.5);
  set_padding (status_label, 10, 10);

  gtk_container_add (GTK_CONTAINER (v2v_output_sw), v2v_output);

  gtk_box_pack_start
    (GTK_BOX (gtk_dialog_get_content_area (GTK_DIALOG (run_dlg))),
     v2v_output_sw, TRUE, TRUE, 0);
  gtk_box_pack_start
    (GTK_BOX (gtk_dialog_get_content_area (GTK_DIALOG (run_dlg))),
     log_label, TRUE, TRUE, 0);
  gtk_box_pack_start
    (GTK_BOX (gtk_dialog_get_content_area (GTK_DIALOG (run_dlg))),
     status_label, TRUE, TRUE, 0);

  /* Shutdown popup menu. */
#ifdef USE_POPOVERS
  shutdown_menu = g_menu_new ();
  g_menu_append (shutdown_menu, _("_Shutdown"), "shutdown.shutdown");
  g_menu_append (shutdown_menu, _("_Reboot"), "shutdown.reboot");

  shutdown_group = g_simple_action_group_new ();
  g_action_map_add_action_entries (G_ACTION_MAP (shutdown_group),
                                   shutdown_actions,
                                   G_N_ELEMENTS (shutdown_actions), NULL);
#else
  shutdown_menu = gtk_menu_new ();
  shutdown_menu_item = gtk_menu_item_new_with_mnemonic (_("_Shutdown"));
  gtk_menu_shell_append (GTK_MENU_SHELL (shutdown_menu), shutdown_menu_item);
  gtk_widget_show (shutdown_menu_item);
  reboot_menu_item = gtk_menu_item_new_with_mnemonic (_("_Reboot"));
  gtk_menu_shell_append (GTK_MENU_SHELL (shutdown_menu), reboot_menu_item);
  gtk_widget_show (reboot_menu_item);
#endif

  /* Buttons. */
  gtk_dialog_add_buttons (GTK_DIALOG (run_dlg),
                          _("_Cancel conversion ..."), 1,
                          NULL);
  cancel_button = gtk_dialog_get_widget_for_response (GTK_DIALOG (run_dlg), 1);
  gtk_widget_set_sensitive (cancel_button, FALSE);
#ifdef USE_POPOVERS
  shutdown_button = gtk_menu_button_new ();
  gtk_button_set_use_underline (GTK_BUTTON (shutdown_button), TRUE);
  gtk_button_set_label (GTK_BUTTON (shutdown_button), _("_Shutdown ..."));
  gtk_button_set_always_show_image (GTK_BUTTON (shutdown_button), TRUE);
  gtk_widget_insert_action_group (shutdown_button, "shutdown",
                                  G_ACTION_GROUP (shutdown_group));
  gtk_menu_button_set_use_popover (GTK_MENU_BUTTON (shutdown_button), TRUE);
  gtk_menu_button_set_menu_model (GTK_MENU_BUTTON (shutdown_button),
                                  G_MENU_MODEL (shutdown_menu));
#else
  shutdown_button = GTK_WIDGET (gtk_menu_tool_button_new (NULL,
                                                          _("_Shutdown ...")));
  gtk_tool_button_set_use_underline (GTK_TOOL_BUTTON (shutdown_button), TRUE);
  gtk_menu_tool_button_set_menu (GTK_MENU_TOOL_BUTTON (shutdown_button),
                                 shutdown_menu);
#endif
  gtk_widget_set_sensitive (shutdown_button, FALSE);
  gtk_dialog_add_action_widget (GTK_DIALOG (run_dlg), shutdown_button, 2);

  /* Signals. */
  g_signal_connect_swapped (G_OBJECT (run_dlg), "delete_event",
                            G_CALLBACK (close_running_dialog), NULL);
  g_signal_connect_swapped (G_OBJECT (run_dlg), "destroy",
                            G_CALLBACK (gtk_main_quit), NULL);
  g_signal_connect (G_OBJECT (cancel_button), "clicked",
                    G_CALLBACK (cancel_conversion_dialog), NULL);
#ifndef USE_POPOVERS
  g_signal_connect (G_OBJECT (shutdown_button), "clicked",
                    G_CALLBACK (shutdown_button_clicked), shutdown_menu);
  g_signal_connect (G_OBJECT (shutdown_menu_item), "activate",
                    G_CALLBACK (shutdown_clicked), NULL);
  g_signal_connect (G_OBJECT (reboot_menu_item), "activate",
                    G_CALLBACK (reboot_clicked), NULL);
#endif
}

/**
 * Hide all other dialogs and show the running dialog.
 */
static void
show_running_dialog (void)
{
  /* Hide the other dialogs. */
  gtk_widget_hide (conn_dlg);
  gtk_widget_hide (conv_dlg);

  /* Show the running dialog. */
  gtk_widget_show_all (run_dlg);
  gtk_widget_set_sensitive (cancel_button, TRUE);
  if (is_iso_environment)
    gtk_widget_set_sensitive (shutdown_button, FALSE);
}

/**
 * Display the remote log directory in the running dialog.
 *
 * If this isn't called from the main thread, then you must only
 * call it via an idle task (C<g_idle_add>).
 *
 * B<NB:> This frees the remote_dir (C<user_data> pointer) which was
 * strdup'd in C<notify_ui_callback>.
 */
static gboolean
set_log_dir (gpointer user_data)
{
  CLEANUP_FREE const char *remote_dir = user_data;
  CLEANUP_FREE char *msg;

  if (asprintf (&msg,
                _("Debug information and log files "
                  "are saved to this directory "
                  "on the conversion server:\n"
                  "%s"),
                remote_dir ? remote_dir : "") == -1)
    error (EXIT_FAILURE, errno, "asprintf");

  gtk_label_set_text (GTK_LABEL (log_label), msg);

  return FALSE;
}

/**
 * Display the conversion status in the running dialog.
 *
 * If this isn't called from the main thread, then you must only
 * call it via an idle task (C<g_idle_add>).
 *
 * B<NB:> This frees the message (C<user_data> pointer) which was
 * strdup'd in C<notify_ui_callback>.
 */
static gboolean
set_status (gpointer user_data)
{
  CLEANUP_FREE const char *msg = user_data;

  gtk_label_set_text (GTK_LABEL (status_label), msg);

  return FALSE;
}

/**
 * Append output from the virt-v2v process to the buffer, and scroll
 * to ensure it is visible.
 *
 * This function is able to parse ANSI colour sequences and more.
 *
 * If this isn't called from the main thread, then you must only
 * call it via an idle task (C<g_idle_add>).
 *
 * B<NB:> This frees the message (C<user_data> pointer) which was
 * strdup'd in C<notify_ui_callback>.
 */
static gboolean
add_v2v_output (gpointer user_data)
{
  CLEANUP_FREE const char *msg = user_data;
  const char *p;
  static size_t linelen = 0;
  static enum {
    state_normal,
    state_escape1,       /* seen ESC, expecting [ */
    state_escape2,       /* seen ESC [, expecting 0 or 1 */
    state_escape3,       /* seen ESC [ 0/1, expecting ; or m */
    state_escape4,       /* seen ESC [ 0/1 ;, expecting 3 */
    state_escape5,       /* seen ESC [ 0/1 ; 3, expecting 1/2/4/5 */
    state_escape6,       /* seen ESC [ 0/1 ; 3 1/2/5/5, expecting m */
    state_cr,            /* seen CR */
    state_truncating,    /* truncating line until next \n */
  } state = state_normal;
  static int colour = 0;
  static GtkTextTag *tag = NULL;
  GtkTextBuffer *buf = gtk_text_view_get_buffer (GTK_TEXT_VIEW (v2v_output));
  GtkTextIter iter, iter2;
  const char *dots = " [...]";

  for (p = msg; *p != '\0'; ++p) {
    char c = *p;

    switch (state) {
    case state_normal:
      if (c == '\r')            /* Start of possible CRLF sequence. */
        state = state_cr;
      else if (c == '\x1b') {   /* Start of an escape sequence. */
        state = state_escape1;
        colour = 0;
      }
      else if (c != '\n' && linelen >= 256) {
        /* Gtk2 (in ~ Fedora 23) has a regression where it takes much
         * longer to display long lines, to the point where the
         * virt-p2v UI would still be slowly displaying kernel modules
         * while the conversion had finished.  For this reason,
         * arbitrarily truncate very long lines.
         */
        gtk_text_buffer_get_end_iter (buf, &iter);
        gtk_text_buffer_insert_with_tags (buf, &iter,
                                          dots, strlen (dots), tag, NULL);
        state = state_truncating;
        colour = 0;
        tag = NULL;
      }
      else {             /* Treat everything else as a normal char. */
        if (c != '\n') linelen++; else linelen = 0;
        gtk_text_buffer_get_end_iter (buf, &iter);
        gtk_text_buffer_insert_with_tags (buf, &iter, &c, 1, tag, NULL);
      }
      break;

    case state_escape1:
      if (c == '[')
        state = state_escape2;
      else
        state = state_normal;
      break;

    case state_escape2:
      if (c == '0')
        state = state_escape3;
      else if (c == '1') {
        state = state_escape3;
        colour += 8;
      }
      else
        state = state_normal;
      break;

    case state_escape3:
      if (c == ';')
        state = state_escape4;
      else if (c == 'm') {
        tag = NULL;             /* restore text colour */
        state = state_normal;
      }
      else
        state = state_normal;
      break;

    case state_escape4:
      if (c == '3')
        state = state_escape5;
      else
        state = state_normal;
      break;

    case state_escape5:
      if (c >= '0' && c <= '7') {
        state = state_escape6;
        colour += c - '0';
      }
      else
        state = state_normal;
      break;

    case state_escape6:
      if (c == 'm') {
        assert (colour >= 0 && colour <= 15);
        tag = v2v_output_tags[colour]; /* set colour tag */
      }
      state = state_normal;
      break;

    case state_cr:
      if (c == '\n')
        /* Process CRLF as single a newline character. */
        p--;
      else {                    /* Delete current (== last) line. */
        linelen = 0;
        gtk_text_buffer_get_end_iter (buf, &iter);
        iter2 = iter;
        gtk_text_iter_set_line_offset (&iter, 0);
        /* Delete from iter..iter2 */
        gtk_text_buffer_delete (buf, &iter, &iter2);
      }
      state = state_normal;
      break;

    case state_truncating:
      if (c == '\n') {
        p--;
        state = state_normal;
      }
      break;
    } /* switch (state) */
  } /* for */

  /* Scroll to the end of the buffer. */
  gtk_text_buffer_get_end_iter (buf, &iter);
  gtk_text_view_scroll_to_iter (GTK_TEXT_VIEW (v2v_output), &iter,
                                0, FALSE, 0., 1.);

  return FALSE;
}

/**
 * Callback when the C<Start conversion> button is clicked.
 */
static void
start_conversion_clicked (GtkWidget *w, gpointer data)
{
  struct config *config = data;
  const char *str;
  char *str2;
  GtkWidget *dlg;
  struct config *copy;
  int err;
  pthread_t tid;
  pthread_attr_t attr;

  /* Unpack dialog fields and check them. */
  free (config->guestname);
  config->guestname = strdup (gtk_entry_get_text (GTK_ENTRY (guestname_entry)));

  if (STREQ (config->guestname, "")) {
    dlg = gtk_message_dialog_new (GTK_WINDOW (conv_dlg),
                                  GTK_DIALOG_DESTROY_WITH_PARENT,
                                  GTK_MESSAGE_ERROR,
                                  GTK_BUTTONS_OK,
                                  _("The guest \"Name\" field is empty."));
    gtk_window_set_title (GTK_WINDOW (dlg), _("Error"));
    gtk_dialog_run (GTK_DIALOG (dlg));
    gtk_widget_destroy (dlg);
    gtk_widget_grab_focus (guestname_entry);
    return;
  }

  config->vcpus = get_vcpus_from_conv_dlg ();
  config->memory = get_memory_from_conv_dlg ();

  /* Get the list of disks to be converted. */
  set_disks_from_ui (config);

  /* The list of disks must be non-empty. */
  if (config->disks == NULL || guestfs_int_count_strings (config->disks) == 0) {
    dlg = gtk_message_dialog_new (GTK_WINDOW (conv_dlg),
                                  GTK_DIALOG_DESTROY_WITH_PARENT,
                                  GTK_MESSAGE_ERROR,
                                  GTK_BUTTONS_OK,
                                  _("No disks were selected for conversion.\n"
                                    "At least one fixed hard disk must be selected.\n"));
    gtk_window_set_title (GTK_WINDOW (dlg), _("Error"));
    gtk_dialog_run (GTK_DIALOG (dlg));
    gtk_widget_destroy (dlg);
    return;
  }

  /* List of removable media and network interfaces. */
  set_removable_from_ui (config);
  set_interfaces_from_ui (config);
  set_network_map_from_ui (config);

  /* Output selection. */
  free (config->output.type);
  config->output.type =
    gtk_combo_box_text_get_active_text (GTK_COMBO_BOX_TEXT (o_combo));

  config->output.allocation = OUTPUT_ALLOCATION_NONE;
  str2 = gtk_combo_box_text_get_active_text (GTK_COMBO_BOX_TEXT (oa_combo));
  if (str2) {
    if (STREQ (str2, "sparse"))
      config->output.allocation = OUTPUT_ALLOCATION_SPARSE;
    else if (STREQ (str2, "preallocated"))
      config->output.allocation = OUTPUT_ALLOCATION_PREALLOCATED;
    free (str2);
  }

  free (config->output.connection);
  str = gtk_entry_get_text (GTK_ENTRY (oc_entry));
  if (str && STRNEQ (str, ""))
    config->output.connection = strdup (str);
  else
    config->output.connection = NULL;

  free (config->output.format);
  str = gtk_entry_get_text (GTK_ENTRY (of_entry));
  if (str && STRNEQ (str, ""))
    config->output.format = strdup (str);
  else
    config->output.format = NULL;

  free (config->output.storage);
  str = gtk_entry_get_text (GTK_ENTRY (os_entry));
  if (str && STRNEQ (str, ""))
    config->output.storage = strdup (str);
  else
    config->output.storage = NULL;

  /* Display the UI for conversion. */
  show_running_dialog ();

  /* Do the conversion, in a background thread. */

  /* Give the conversion (background) thread its own copy of the
   * config in case we update the config in the main thread.
   */
  copy = copy_config (config);

  pthread_attr_init (&attr);
  pthread_attr_setdetachstate (&attr, PTHREAD_CREATE_DETACHED);
  err = pthread_create (&tid, &attr, start_conversion_thread, copy);
  if (err != 0)
    error (EXIT_FAILURE, err, "pthread_create");
  pthread_attr_destroy (&attr);
}

/**
 * This is the background thread which performs the conversion.
 */
static void *
start_conversion_thread (void *data)
{
  struct config *copy = data;
  int r;

  r = start_conversion (copy, notify_ui_callback);
  free_config (copy);

  if (r == -1)
    g_idle_add (conversion_error, NULL);
  else
    g_idle_add (conversion_finished, NULL);

  /* Thread is detached anyway, so no one is waiting for the status. */
  return NULL;
}

/**
 * Idle task called from C<start_conversion_thread> (but run on the
 * main thread) when there was an error during the conversion.
 */
static gboolean
conversion_error (gpointer user_data)
{
  const char *err = get_conversion_error ();
  GtkWidget *dlg;

  dlg = gtk_message_dialog_new (GTK_WINDOW (run_dlg),
                                GTK_DIALOG_DESTROY_WITH_PARENT,
                                GTK_MESSAGE_ERROR,
                                GTK_BUTTONS_OK,
                                _("Conversion failed: %s"), err);
  gtk_window_set_title (GTK_WINDOW (dlg), _("Conversion failed"));
  gtk_dialog_run (GTK_DIALOG (dlg));
  gtk_widget_destroy (dlg);

  /* Disable the cancel button. */
  gtk_widget_set_sensitive (cancel_button, FALSE);

  /* Enable the shutdown button. */
  if (is_iso_environment)
    gtk_widget_set_sensitive (shutdown_button, TRUE);

  return FALSE;
}

/**
 * Idle task called from C<start_conversion_thread> (but run on the
 * main thread) when the conversion completed without errors.
 */
static gboolean
conversion_finished (gpointer user_data)
{
  GtkWidget *dlg;

  dlg = gtk_message_dialog_new (GTK_WINDOW (run_dlg),
                                GTK_DIALOG_DESTROY_WITH_PARENT,
                                GTK_MESSAGE_INFO,
                                GTK_BUTTONS_OK,
                                _("The conversion was successful."));
  gtk_window_set_title (GTK_WINDOW (dlg), _("Conversion was successful"));
  gtk_dialog_run (GTK_DIALOG (dlg));
  gtk_widget_destroy (dlg);

  /* Disable the cancel button. */
  gtk_widget_set_sensitive (cancel_button, FALSE);

  /* Enable the shutdown button. */
  if (is_iso_environment)
    gtk_widget_set_sensitive (shutdown_button, TRUE);

  return FALSE;
}

/**
 * This is called from F<conversion.c>:C<start_conversion>
 * when there is a status change or a log message.
 */
static void
notify_ui_callback (int type, const char *data)
{
  /* Because we call the functions as idle callbacks which run
   * in the main thread some time later, we must duplicate the
   * 'data' parameter (which is always a \0-terminated string).
   *
   * This is freed by the idle task function.
   */
  char *copy = strdup (data);

  switch (type) {
  case NOTIFY_LOG_DIR:
    g_idle_add (set_log_dir, (gpointer) copy);
    break;

  case NOTIFY_REMOTE_MESSAGE:
    g_idle_add (add_v2v_output, (gpointer) copy);
    break;

  case NOTIFY_STATUS:
    g_idle_add (set_status, (gpointer) copy);
    break;

  default:
    fprintf (stderr,
             "%s: unknown message during conversion: type=%d data=%s\n",
             getprogname (), type, data);
    free (copy);
  }
}

static gboolean
close_running_dialog (GtkWidget *w, GdkEvent *event, gpointer data)
{
  /* This function is called if the user tries to close the running
   * dialog.  This is the same as cancelling the conversion.
   */
  if (conversion_is_running ()) {
    cancel_conversion ();
    return TRUE;
  }
  else
    /* Conversion is not running, so this will delete the dialog. */
    return FALSE;
}

/**
 * This is called when the user clicks on the "Cancel conversion"
 * button.  Since conversions can run for a long time, and cancelling
 * the conversion is non-recoverable, this function displays a
 * confirmation dialog before cancelling the conversion.
 */
static void
cancel_conversion_dialog (GtkWidget *w, gpointer data)
{
  GtkWidget *dlg;

  if (!conversion_is_running ())
    return;

  dlg = gtk_message_dialog_new (GTK_WINDOW (run_dlg),
                                GTK_DIALOG_DESTROY_WITH_PARENT,
                                GTK_MESSAGE_QUESTION,
                                GTK_BUTTONS_YES_NO,
                                _("Really cancel the conversion? "
                                  "To convert this machine you will need to "
                                  "re-run the conversion from the beginning."));
  gtk_window_set_title (GTK_WINDOW (dlg), _("Cancel the conversion"));
  if (gtk_dialog_run (GTK_DIALOG (dlg)) == GTK_RESPONSE_YES)
    /* This makes start_conversion return an error (eventually). */
    cancel_conversion ();

  gtk_widget_destroy (dlg);
}

#ifdef USE_POPOVERS
static void
activate_action (GSimpleAction *action, GVariant *parameter, gpointer user_data)
{
  const char *action_name = g_action_get_name (G_ACTION (action));
  if (STREQ (action_name, "shutdown"))
    shutdown_clicked (NULL, user_data);
  else if (STREQ (action_name, "reboot"))
    reboot_clicked (NULL, user_data);
}
#else
static void
shutdown_button_clicked (GtkToolButton *w, gpointer data)
{
  GtkMenu *menu = data;

  gtk_menu_popup (menu, NULL, NULL, NULL, NULL, 1,
                  gtk_get_current_event_time ());
}
#endif

static void
shutdown_clicked (GtkWidget *w, gpointer data)
{
  if (!is_iso_environment)
    return;

  sync ();
  sleep (2);
  ignore_value (system ("/sbin/poweroff"));
}

static void
reboot_clicked (GtkWidget *w, gpointer data)
{
  if (!is_iso_environment)
    return;

  sync ();
  sleep (2);
  ignore_value (system ("/sbin/reboot"));
}
