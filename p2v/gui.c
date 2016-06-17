/* virt-p2v
 * Copyright (C) 2009-2016 Red Hat Inc.
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

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>

#include <pthread.h>

#pragma GCC diagnostic ignored "-Wstrict-prototypes" /* error in <gtk.h> */
#include <gtk/gtk.h>

#include "ignore-value.h"

#include "p2v.h"

/* Interactive GUI configuration. */

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
  *spinner_hbox, *spinner, *spinner_message, *next_button;

/* The conversion dialog. */
static GtkWidget *conv_dlg,
  *guestname_entry, *vcpus_entry, *memory_entry,
  *vcpus_warning, *memory_warning, *target_warning_label,
  *o_combo, *oc_entry, *os_entry, *of_entry, *oa_combo,
  *info_label,
  *debug_button,
  *disks_list, *removable_list, *interfaces_list,
  *start_button;

/* The running dialog which is displayed when virt-v2v is running. */
static GtkWidget *run_dlg,
  *v2v_output_sw, *v2v_output, *log_label, *status_label,
  *cancel_button, *reboot_button;

/* The entry point from the main program.
 * Note that gtk_init etc have already been called in main.
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
  gdk_threads_leave ();
}

/*----------------------------------------------------------------------*/
/* Connection dialog. */

static void password_or_identity_changed_callback (GtkWidget *w, gpointer data);
static void test_connection_clicked (GtkWidget *w, gpointer data);
static void *test_connection_thread (void *data);
static void configure_network_button_clicked (GtkWidget *w, gpointer data);
static void xterm_button_clicked (GtkWidget *w, gpointer data);
static void about_button_clicked (GtkWidget *w, gpointer data);
static void connection_next_clicked (GtkWidget *w, gpointer data);
static void repopulate_output_combo (struct config *config);

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
  gtk_window_set_title (GTK_WINDOW (conn_dlg), guestfs_int_program_name);
  gtk_window_set_resizable (GTK_WINDOW (conn_dlg), FALSE);

  /* The main dialog area. */
  intro = gtk_label_new (_("Connect to a virt-v2v conversion server over SSH:"));
  gtk_label_set_line_wrap (GTK_LABEL (intro), TRUE);
  gtk_misc_set_padding (GTK_MISC (intro), 10, 10);

  table = gtk_table_new (5, 2, FALSE);
  server_label = gtk_label_new (_("Conversion server:"));
  gtk_misc_set_alignment (GTK_MISC (server_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (table), server_label,
                    0, 1, 0, 1, GTK_FILL, GTK_FILL, 4, 4);
  server_hbox = gtk_hbox_new (FALSE, 4);
  server_entry = gtk_entry_new ();
  if (config->server != NULL)
    gtk_entry_set_text (GTK_ENTRY (server_entry), config->server);
  port_colon_label = gtk_label_new (":");
  port_entry = gtk_entry_new ();
  gtk_entry_set_width_chars (GTK_ENTRY (port_entry), 6);
  snprintf (port_str, sizeof port_str, "%d", config->port);
  gtk_entry_set_text (GTK_ENTRY (port_entry), port_str);
  gtk_box_pack_start (GTK_BOX (server_hbox), server_entry, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (server_hbox), port_colon_label, FALSE, FALSE, 0);
  gtk_box_pack_start (GTK_BOX (server_hbox), port_entry, FALSE, FALSE, 0);
  gtk_table_attach (GTK_TABLE (table), server_hbox,
                    1, 2, 0, 1, GTK_EXPAND|GTK_FILL, GTK_FILL, 4, 4);

  username_label = gtk_label_new (_("User name:"));
  gtk_misc_set_alignment (GTK_MISC (username_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (table), username_label,
                    0, 1, 1, 2, GTK_FILL, GTK_FILL, 4, 4);
  username_entry = gtk_entry_new ();
  if (config->username != NULL)
    gtk_entry_set_text (GTK_ENTRY (username_entry), config->username);
  else
    gtk_entry_set_text (GTK_ENTRY (username_entry), "root");
  gtk_table_attach (GTK_TABLE (table), username_entry,
                    1, 2, 1, 2, GTK_EXPAND|GTK_FILL, GTK_FILL, 4, 4);

  password_label = gtk_label_new (_("Password:"));
  gtk_misc_set_alignment (GTK_MISC (password_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (table), password_label,
                    0, 1, 2, 3, GTK_FILL, GTK_FILL, 4, 4);
  password_entry = gtk_entry_new ();
  gtk_entry_set_visibility (GTK_ENTRY (password_entry), FALSE);
#ifdef GTK_INPUT_PURPOSE_PASSWORD
  gtk_entry_set_input_purpose (GTK_ENTRY (password_entry),
                               GTK_INPUT_PURPOSE_PASSWORD);
#endif
  if (config->password != NULL)
    gtk_entry_set_text (GTK_ENTRY (password_entry), config->password);
  gtk_table_attach (GTK_TABLE (table), password_entry,
                    1, 2, 2, 3, GTK_EXPAND|GTK_FILL, GTK_FILL, 4, 4);

  identity_label = gtk_label_new (_("SSH Identity URL:"));
  gtk_misc_set_alignment (GTK_MISC (identity_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (table), identity_label,
                    0, 1, 3, 4, GTK_FILL, GTK_FILL, 4, 4);
  identity_entry = gtk_entry_new ();
  if (config->identity_url != NULL)
    gtk_entry_set_text (GTK_ENTRY (identity_entry), config->identity_url);
  gtk_table_attach (GTK_TABLE (table), identity_entry,
                    1, 2, 3, 4, GTK_EXPAND|GTK_FILL, GTK_FILL, 4, 4);

  sudo_button =
    gtk_check_button_new_with_label (_("Use sudo when running virt-v2v"));
  gtk_toggle_button_set_active (GTK_TOGGLE_BUTTON (sudo_button),
                                config->sudo);
  gtk_table_attach (GTK_TABLE (table), sudo_button,
                    1, 2, 4, 5, GTK_FILL, GTK_FILL, 4, 4);

  test_hbox = gtk_hbox_new (FALSE, 0);
  test = gtk_button_new_with_label (_("Test connection"));
  gtk_box_pack_start (GTK_BOX (test_hbox), test, TRUE, FALSE, 0);

  spinner_hbox = gtk_hbox_new (FALSE, 10);
  spinner = gtk_spinner_new ();
  gtk_box_pack_start (GTK_BOX (spinner_hbox), spinner, FALSE, FALSE, 0);
  spinner_message = gtk_label_new (NULL);
  gtk_label_set_line_wrap (GTK_LABEL (spinner_message), TRUE);
  gtk_misc_set_padding (GTK_MISC (spinner_message), 10, 10);
  gtk_box_pack_start (GTK_BOX (spinner_hbox), spinner_message, TRUE, TRUE, 0);

  gtk_box_pack_start (GTK_BOX (GTK_DIALOG (conn_dlg)->vbox),
                      intro, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (GTK_DIALOG (conn_dlg)->vbox),
                      table, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (GTK_DIALOG (conn_dlg)->vbox),
                      test_hbox, FALSE, FALSE, 0);
  gtk_box_pack_start (GTK_BOX (GTK_DIALOG (conn_dlg)->vbox),
                      spinner_hbox, TRUE, TRUE, 0);

  /* Buttons. */
  gtk_dialog_add_buttons (GTK_DIALOG (conn_dlg),
                          _("Configure network ..."), 1,
                          _("XTerm ..."), 2,
                          _("About virt-p2v " PACKAGE_VERSION " ..."), 3,
                          _("Next"), 4,
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
  g_signal_connect (G_OBJECT (password_entry), "changed",
                    G_CALLBACK (password_or_identity_changed_callback), NULL);
  g_signal_connect (G_OBJECT (identity_entry), "changed",
                    G_CALLBACK (password_or_identity_changed_callback), NULL);
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

static void
show_connection_dialog (void)
{
  /* Hide the other dialogs. */
  gtk_widget_hide (conv_dlg);
  gtk_widget_hide (run_dlg);

  /* Show everything except the spinner. */
  gtk_widget_show_all (conn_dlg);
  gtk_widget_hide_all (spinner_hbox);
}

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
  gtk_widget_hide (spinner);

  /* Get the fields from the various widgets. */
  free (config->server);
  config->server = strdup (gtk_entry_get_text (GTK_ENTRY (server_entry)));
  if (STREQ (config->server, "")) {
    gtk_label_set_text (GTK_LABEL (spinner_message),
                        _("error: No conversion server given."));
    gtk_widget_grab_focus (server_entry);
    errors++;
  }
  port_str = gtk_entry_get_text (GTK_ENTRY (port_entry));
  if (sscanf (port_str, "%d", &config->port) != 1 ||
      config->port <= 0 || config->port >= 65536) {
    gtk_label_set_text (GTK_LABEL (spinner_message),
                        _("error: Invalid port number. If in doubt, use \"22\"."));
    gtk_widget_grab_focus (port_entry);
    errors++;
  }
  free (config->username);
  config->username = strdup (gtk_entry_get_text (GTK_ENTRY (username_entry)));
  if (STREQ (config->username, "")) {
    gtk_label_set_text (GTK_LABEL (spinner_message),
                        _("error: No user name.  If in doubt, use \"root\"."));
    gtk_widget_grab_focus (username_entry);
    errors++;
  }
  free (config->password);
  config->password = strdup (gtk_entry_get_text (GTK_ENTRY (password_entry)));

  free (config->identity_url);
  identity_str = gtk_entry_get_text (GTK_ENTRY (identity_entry));
  if (identity_str && STRNEQ (identity_str, ""))
    config->identity_url = strdup (identity_str);
  else
    config->identity_url = NULL;
  config->identity_file_needs_update = 1;

  config->sudo = gtk_toggle_button_get_active (GTK_TOGGLE_BUTTON (sudo_button));

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
  if (err != 0) {
    fprintf (stderr, "pthread_create: %s\n", strerror (err));
    exit (EXIT_FAILURE);
  }
  pthread_attr_destroy (&attr);
}

/* Run test_connection (in a detached background thread).  Once it
 * finishes stop the spinner and set the spinner message
 * appropriately.  If the test is successful then we enable the "Next"
 * button.
 */
static void *
test_connection_thread (void *data)
{
  struct config *copy = data;
  int r;

  gdk_threads_enter ();
  gtk_label_set_text (GTK_LABEL (spinner_message),
                      _("Testing the connection to the conversion server ..."));
  gtk_widget_show (spinner);
  gtk_spinner_start (GTK_SPINNER (spinner));
  gdk_threads_leave ();

  wait_network_online (copy);
  r = test_connection (copy);
  free_config (copy);

  gdk_threads_enter ();
  gtk_spinner_stop (GTK_SPINNER (spinner));
  gtk_widget_hide (spinner);

  if (r == -1) {
    /* Error testing the connection. */
    const char *err = get_ssh_error ();

    gtk_label_set_text (GTK_LABEL (spinner_message), err);
    /* Disable the Next button. */
    gtk_widget_set_sensitive (next_button, FALSE);
  }
  else {
    /* Connection is good. */
    gtk_label_set_text (GTK_LABEL (spinner_message),
                        _("Connected to the conversion server.\n"
                          "Press the \"Next\" button to configure the conversion process."));
    /* Enable the Next button. */
    gtk_widget_set_sensitive (next_button, TRUE);
    gtk_widget_grab_focus (next_button);

    /* Update the information in the conversion dialog. */
    set_info_label ();
  }
  gdk_threads_leave ();

  /* Thread is detached anyway, so no one is waiting for the status. */
  return NULL;
}

static void
configure_network_button_clicked (GtkWidget *w, gpointer data)
{
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

static void
about_button_clicked (GtkWidget *w, gpointer data)
{
  gtk_show_about_dialog (GTK_WINDOW (conn_dlg),
                         "program-name", guestfs_int_program_name,
                         "version", PACKAGE_VERSION_FULL " (" host_cpu ")",
                         "copyright", "\u00A9 2009-2016 Red Hat Inc.",
                         "comments",
                           _("Virtualize a physical machine to run on KVM"),
                         "license", gplv2plus,
                         "website", "http://libguestfs.org/",
                         "authors", authors,
                         NULL);
}

/* The connection dialog Next button has been clicked. */
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
  DISKS_COL_SIZE,
  DISKS_COL_MODEL,
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
  gtk_window_set_title (GTK_WINDOW (conv_dlg), guestfs_int_program_name);
  gtk_window_set_resizable (GTK_WINDOW (conv_dlg), FALSE);
  /* XXX It would be nice not to have to set this explicitly, but
   * if we don't then Gtk chooses a very small window.
   */
  gtk_widget_set_size_request (conv_dlg, 900, 560);

  /* The main dialog area. */
  hbox = gtk_hbox_new (TRUE, 1);
  left_vbox = gtk_vbox_new (FALSE, 1);
  right_vbox = gtk_vbox_new (TRUE, 1);

  /* The left column: target properties and output options. */
  target_frame = gtk_frame_new (_("Target properties"));
  gtk_container_set_border_width (GTK_CONTAINER (target_frame), 4);

  target_vbox = gtk_vbox_new (FALSE, 1);

  target_tbl = gtk_table_new (3, 3, FALSE);
  guestname_label = gtk_label_new (_("Name:"));
  gtk_misc_set_alignment (GTK_MISC (guestname_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (target_tbl), guestname_label,
                    0, 1, 0, 1, GTK_FILL, GTK_FILL, 1, 1);
  guestname_entry = gtk_entry_new ();
  if (config->guestname != NULL)
    gtk_entry_set_text (GTK_ENTRY (guestname_entry), config->guestname);
  gtk_table_attach (GTK_TABLE (target_tbl), guestname_entry,
                    1, 2, 0, 1, GTK_FILL, GTK_FILL, 1, 1);

  vcpus_label = gtk_label_new (_("# vCPUs:"));
  gtk_misc_set_alignment (GTK_MISC (vcpus_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (target_tbl), vcpus_label,
                    0, 1, 1, 2, GTK_FILL, GTK_FILL, 1, 1);
  vcpus_entry = gtk_entry_new ();
  snprintf (vcpus_str, sizeof vcpus_str, "%d", config->vcpus);
  gtk_entry_set_text (GTK_ENTRY (vcpus_entry), vcpus_str);
  gtk_table_attach (GTK_TABLE (target_tbl), vcpus_entry,
                    1, 2, 1, 2, GTK_FILL, GTK_FILL, 1, 1);
  vcpus_warning = gtk_image_new_from_stock (GTK_STOCK_DIALOG_WARNING,
                                            GTK_ICON_SIZE_BUTTON);
  gtk_table_attach (GTK_TABLE (target_tbl), vcpus_warning,
                    2, 3, 1, 2, 0, 0, 1, 1);

  memory_label = gtk_label_new (_("Memory (MB):"));
  gtk_misc_set_alignment (GTK_MISC (memory_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (target_tbl), memory_label,
                    0, 1, 2, 3, GTK_FILL, GTK_FILL, 1, 1);
  memory_entry = gtk_entry_new ();
  snprintf (memory_str, sizeof memory_str, "%" PRIu64,
            config->memory / 1024 / 1024);
  gtk_entry_set_text (GTK_ENTRY (memory_entry), memory_str);
  gtk_table_attach (GTK_TABLE (target_tbl), memory_entry,
                    1, 2, 2, 3, GTK_FILL, GTK_FILL, 1, 1);
  memory_warning = gtk_image_new_from_stock (GTK_STOCK_DIALOG_WARNING,
                                             GTK_ICON_SIZE_BUTTON);
  gtk_table_attach (GTK_TABLE (target_tbl), memory_warning,
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

  output_vbox = gtk_vbox_new (FALSE, 1);

  output_tbl = gtk_table_new (5, 2, FALSE);
  o_label = gtk_label_new (_("Output to (-o):"));
  gtk_misc_set_alignment (GTK_MISC (o_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (output_tbl), o_label,
                    0, 1, 0, 1, GTK_FILL, GTK_FILL, 1, 1);
  o_combo = gtk_combo_box_text_new ();
  gtk_widget_set_tooltip_markup (o_combo, _("<b>libvirt</b> means send the converted guest to libvirt-managed KVM on the conversion server.  <b>local</b> means put it in a directory on the conversion server.  <b>rhev</b> means write it to RHEV-M/oVirt.  <b>glance</b> means write it to OpenStack Glance.  See the virt-v2v(1) manual page for more information about output options."));
  repopulate_output_combo (config);
  gtk_table_attach (GTK_TABLE (output_tbl), o_combo,
                    1, 2, 0, 1, GTK_FILL, GTK_FILL, 1, 1);

  oc_label = gtk_label_new (_("Output conn. (-oc):"));
  gtk_misc_set_alignment (GTK_MISC (oc_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (output_tbl), oc_label,
                    0, 1, 1, 2, GTK_FILL, GTK_FILL, 1, 1);
  oc_entry = gtk_entry_new ();
  gtk_widget_set_tooltip_markup (oc_entry, _("For <b>libvirt</b> only, the libvirt connection URI, or leave blank to add the guest to the default libvirt instance on the conversion server.  For others, leave this field blank."));
  if (config->output_connection != NULL)
    gtk_entry_set_text (GTK_ENTRY (oc_entry), config->output_connection);
  gtk_table_attach (GTK_TABLE (output_tbl), oc_entry,
                    1, 2, 1, 2, GTK_FILL, GTK_FILL, 1, 1);

  os_label = gtk_label_new (_("Output storage (-os):"));
  gtk_misc_set_alignment (GTK_MISC (os_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (output_tbl), os_label,
                    0, 1, 2, 3, GTK_FILL, GTK_FILL, 1, 1);
  os_entry = gtk_entry_new ();
  gtk_widget_set_tooltip_markup (os_entry, _("For <b>local</b>, put the directory name on the conversion server.  For <b>rhev</b>, put the Export Storage Domain (server:/mountpoint).  For others, leave this field blank."));
  if (config->output_storage != NULL)
    gtk_entry_set_text (GTK_ENTRY (os_entry), config->output_storage);
  gtk_table_attach (GTK_TABLE (output_tbl), os_entry,
                    1, 2, 2, 3, GTK_FILL, GTK_FILL, 1, 1);

  of_label = gtk_label_new (_("Output format (-of):"));
  gtk_misc_set_alignment (GTK_MISC (of_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (output_tbl), of_label,
                    0, 1, 3, 4, GTK_FILL, GTK_FILL, 1, 1);
  of_entry = gtk_entry_new ();
  gtk_widget_set_tooltip_markup (of_entry, _("The output disk format, typically <b>raw</b> or <b>qcow2</b>.  If blank, defaults to <b>raw</b>."));
  if (config->output_format != NULL)
    gtk_entry_set_text (GTK_ENTRY (of_entry), config->output_format);
  gtk_table_attach (GTK_TABLE (output_tbl), of_entry,
                    1, 2, 3, 4, GTK_FILL, GTK_FILL, 1, 1);

  oa_label = gtk_label_new (_("Output allocation (-oa):"));
  gtk_misc_set_alignment (GTK_MISC (oa_label), 1., 0.5);
  gtk_table_attach (GTK_TABLE (output_tbl), oa_label,
                    0, 1, 4, 5, GTK_FILL, GTK_FILL, 1, 1);
  oa_combo = gtk_combo_box_text_new ();
  gtk_combo_box_text_append_text (GTK_COMBO_BOX_TEXT (oa_combo),
                                  "sparse");
  gtk_combo_box_text_append_text (GTK_COMBO_BOX_TEXT (oa_combo),
                                  "preallocated");
  switch (config->output_allocation) {
  case OUTPUT_ALLOCATION_PREALLOCATED:
    gtk_combo_box_set_active (GTK_COMBO_BOX (oa_combo), 1);
    break;
  default:
    gtk_combo_box_set_active (GTK_COMBO_BOX (oa_combo), 0);
    break;
  }
  gtk_table_attach (GTK_TABLE (output_tbl), oa_combo,
                    1, 2, 4, 5, GTK_FILL, GTK_FILL, 1, 1);

  debug_button =
    gtk_check_button_new_with_label (_("Enable server-side debugging\n"
                                       "(This is saved in /tmp on the conversion server)"));
  gtk_toggle_button_set_active (GTK_TOGGLE_BUTTON (debug_button),
                                config->verbose);

  gtk_box_pack_start (GTK_BOX (output_vbox), output_tbl, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (output_vbox), debug_button, TRUE, TRUE, 0);
  gtk_container_add (GTK_CONTAINER (output_frame), output_vbox);

  info_frame = gtk_frame_new (_("Information"));
  gtk_container_set_border_width (GTK_CONTAINER (info_frame), 4);
  info_label = gtk_label_new (NULL);
  gtk_misc_set_alignment (GTK_MISC (info_label), 0.1, 0.5);
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
  gtk_scrolled_window_add_with_viewport (GTK_SCROLLED_WINDOW (disks_sw),
                                         disks_list);
  gtk_container_add (GTK_CONTAINER (disks_frame), disks_sw);

  removable_frame = gtk_frame_new (_("Removable media"));
  gtk_container_set_border_width (GTK_CONTAINER (removable_frame), 4);
  removable_sw = gtk_scrolled_window_new (NULL, NULL);
  gtk_container_set_border_width (GTK_CONTAINER (removable_sw), 8);
  gtk_scrolled_window_set_policy (GTK_SCROLLED_WINDOW (removable_sw),
                                  GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  removable_list = gtk_tree_view_new ();
  populate_removable (GTK_TREE_VIEW (removable_list));
  gtk_scrolled_window_add_with_viewport (GTK_SCROLLED_WINDOW (removable_sw),
                                         removable_list);
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
  gtk_scrolled_window_add_with_viewport (GTK_SCROLLED_WINDOW (interfaces_sw),
                                         interfaces_list);
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
  gtk_box_pack_start (GTK_BOX (GTK_DIALOG (conv_dlg)->vbox),
                      hbox, TRUE, TRUE, 0);

  /* Buttons. */
  gtk_dialog_add_buttons (GTK_DIALOG (conv_dlg),
                          _("Back"), 1,
                          _("Start conversion"), 2,
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

/* Update the information in the conversion dialog. */
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

static void
repopulate_output_combo (struct config *config)
{
  GtkTreeModel *model;
  CLEANUP_FREE char *output;
  size_t i;

  /* Which driver is currently selected? */
  if (config && config->output)
    output = strdup (config->output);
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

static void
populate_disks (GtkTreeView *disks_list)
{
  GtkListStore *disks_store;
  GtkCellRenderer *disks_col_convert, *disks_col_device,
    *disks_col_size, *disks_col_model;
  GtkTreeIter iter;
  size_t i;

  disks_store = gtk_list_store_new (NUM_DISKS_COLS,
                                    G_TYPE_BOOLEAN, G_TYPE_STRING,
                                    G_TYPE_STRING, G_TYPE_STRING);
  if (all_disks != NULL) {
    for (i = 0; all_disks[i] != NULL; ++i) {
      CLEANUP_FREE char *size_filename = NULL;
      CLEANUP_FREE char *model_filename = NULL;
      CLEANUP_FREE char *size_str = NULL;
      CLEANUP_FREE char *size_gb = NULL;
      CLEANUP_FREE char *model = NULL;
      uint64_t size;

      if (asprintf (&size_filename, "/sys/block/%s/size",
                    all_disks[i]) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
      if (g_file_get_contents (size_filename, &size_str, NULL, NULL) &&
          sscanf (size_str, "%" SCNu64, &size) == 1) {
        size /= 2*1024*1024; /* size from kernel is given in sectors? */
        if (asprintf (&size_gb, "%" PRIu64, size) == -1) {
          perror ("asprintf");
          exit (EXIT_FAILURE);
        }
      }

      if (asprintf (&model_filename, "/sys/block/%s/device/model",
                    all_disks[i]) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
      if (g_file_get_contents (model_filename, &model, NULL, NULL)) {
        /* Need to chomp trailing \n from the content. */
        size_t len = strlen (model);
        if (len > 0 && model[len-1] == '\n')
          model[len-1] = '\0';
      } else {
        model = strdup ("");
      }

      gtk_list_store_append (disks_store, &iter);
      gtk_list_store_set (disks_store, &iter,
                          DISKS_COL_CONVERT, TRUE,
                          DISKS_COL_DEVICE, all_disks[i],
                          DISKS_COL_SIZE, size_gb,
                          DISKS_COL_MODEL, model,
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
                                               "text", DISKS_COL_DEVICE,
                                               NULL);
  gtk_cell_renderer_set_alignment (disks_col_device, 0.0, 0.0);
  disks_col_size = gtk_cell_renderer_text_new ();
  gtk_tree_view_insert_column_with_attributes (disks_list,
                                               -1,
                                               _("Size (GB)"),
                                               disks_col_size,
                                               "text", DISKS_COL_SIZE,
                                               NULL);
  gtk_cell_renderer_set_alignment (disks_col_size, 0.0, 0.0);
  disks_col_model = gtk_cell_renderer_text_new ();
  gtk_tree_view_insert_column_with_attributes (disks_list,
                                               -1,
                                               _("Model"),
                                               disks_col_model,
                                               "text", DISKS_COL_MODEL,
                                               NULL);
  gtk_cell_renderer_set_alignment (disks_col_model, 0.0, 0.0);

  g_signal_connect (disks_col_convert, "toggled",
                    G_CALLBACK (toggled), disks_store);
}

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
      gtk_list_store_append (removable_store, &iter);
      gtk_list_store_set (removable_store, &iter,
                          REMOVABLE_COL_CONVERT, TRUE,
                          REMOVABLE_COL_DEVICE, all_removable[i],
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
                                               "text", REMOVABLE_COL_DEVICE,
                                               NULL);
  gtk_cell_renderer_set_alignment (removable_col_device, 0.0, 0.0);

  g_signal_connect (removable_col_convert, "toggled",
                    G_CALLBACK (toggled), removable_store);
}

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
                    if_vendor ? : _("Unknown")) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }

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

/* When the user clicks on the interface name on the list of
 * interfaces, we want to run 'ethtool --identify', which usually
 * makes some lights flash on the physical interface.  We cannot catch
 * clicks on the cell itself, so we have to go via a more obscure
 * route.  See http://stackoverflow.com/a/27207433 and
 * https://en.wikibooks.org/wiki/GTK%2B_By_Example/Tree_View/Events
 */
static gboolean
maybe_identify_click (GtkWidget *interfaces_list, GdkEventButton *event,
                      gpointer data)
{
  gboolean ret = FALSE;         /* Did we handle this event? */

  /* Single left click only. */
  if (event->type == GDK_BUTTON_PRESS && event->button == 1) {
    GtkTreePath *path;
    GtkTreeViewColumn *column;

    if (gtk_tree_view_get_path_at_pos (GTK_TREE_VIEW (interfaces_list),
                                       event->x, event->y,
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
        if (asprintf (&cmd, "ethtool --identify '%s' 10 &", if_name) == -1) {
          perror ("asprintf");
          exit (EXIT_FAILURE);
        }
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
  if (*ret == NULL) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }
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
  if (config->network_map == NULL) {
    perror ("malloc");
    exit (EXIT_FAILURE);
  }
  i = j = 0;

  b = gtk_tree_model_get_iter_first (model, &iter);
  while (b) {
    gtk_tree_model_get (model, &iter, INTERFACES_COL_NETWORK, &s, -1);
    if (s) {
      assert (all_interfaces[i] != NULL);
      if (asprintf (&config->network_map[j], "%s:%s",
                    all_interfaces[i], s) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
      ++j;
    }
    b = gtk_tree_model_iter_next (model, &iter);
    ++i;
  }

  config->network_map[j] = NULL;
}

/* The conversion dialog Back button has been clicked. */
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

/* Display a warning if the vCPUs or memory is outside the supported
 * range.  (RHBZ#823758).  See also:
 * https://access.redhat.com/articles/rhel-kvm-limits
 */
#define MAX_SUPPORTED_VCPUS 160
#define MAX_SUPPORTED_MEMORY_MB (UINT64_C (4000 * 1024))

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
    if (warning == NULL) {
    malloc_fail:
      perror ("malloc");
      exit (EXIT_FAILURE);
    }
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

static void set_log_dir (const char *remote_dir);
static void set_status (const char *msg);
static void add_v2v_output (const char *msg);
static void add_v2v_output_2 (const char *msg, size_t len);
static void *start_conversion_thread (void *data);
static void cancel_conversion_clicked (GtkWidget *w, gpointer data);
static void reboot_clicked (GtkWidget *w, gpointer data);
static gboolean close_running_dialog (GtkWidget *w, GdkEvent *event, gpointer data);

static void
create_running_dialog (void)
{
  run_dlg = gtk_dialog_new ();
  gtk_window_set_title (GTK_WINDOW (run_dlg), guestfs_int_program_name);
  gtk_window_set_resizable (GTK_WINDOW (run_dlg), FALSE);

  /* The main dialog area. */
  v2v_output_sw = gtk_scrolled_window_new (NULL, NULL);
  gtk_scrolled_window_set_policy (GTK_SCROLLED_WINDOW (v2v_output_sw),
                                  GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  v2v_output = gtk_text_view_new ();
  gtk_text_view_set_editable (GTK_TEXT_VIEW (v2v_output), FALSE);
  gtk_text_view_set_wrap_mode (GTK_TEXT_VIEW (v2v_output), GTK_WRAP_CHAR);
  gtk_widget_set_size_request (v2v_output, 700, 400);
  log_label = gtk_label_new (NULL);
  gtk_misc_set_alignment (GTK_MISC (log_label), 0., 0.5);
  gtk_misc_set_padding (GTK_MISC (log_label), 10, 10);
  set_log_dir (NULL);
  status_label = gtk_label_new (NULL);
  gtk_misc_set_alignment (GTK_MISC (status_label), 0., 0.5);
  gtk_misc_set_padding (GTK_MISC (status_label), 10, 10);

  gtk_container_add (GTK_CONTAINER (v2v_output_sw), v2v_output);

  gtk_box_pack_start (GTK_BOX (GTK_DIALOG (run_dlg)->vbox),
                      v2v_output_sw, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (GTK_DIALOG (run_dlg)->vbox),
                      log_label, TRUE, TRUE, 0);
  gtk_box_pack_start (GTK_BOX (GTK_DIALOG (run_dlg)->vbox),
                      status_label, TRUE, TRUE, 0);

  /* Buttons. */
  gtk_dialog_add_buttons (GTK_DIALOG (run_dlg),
                          _("Cancel conversion"), 1,
                          _("Reboot"), 2,
                          NULL);
  cancel_button = gtk_dialog_get_widget_for_response (GTK_DIALOG (run_dlg), 1);
  gtk_widget_set_sensitive (cancel_button, FALSE);
  reboot_button = gtk_dialog_get_widget_for_response (GTK_DIALOG (run_dlg), 2);
  gtk_widget_set_sensitive (reboot_button, FALSE);

  /* Signals. */
  g_signal_connect_swapped (G_OBJECT (run_dlg), "delete_event",
                            G_CALLBACK (close_running_dialog), NULL);
  g_signal_connect_swapped (G_OBJECT (run_dlg), "destroy",
                            G_CALLBACK (gtk_main_quit), NULL);
  g_signal_connect (G_OBJECT (cancel_button), "clicked",
                    G_CALLBACK (cancel_conversion_clicked), NULL);
  g_signal_connect (G_OBJECT (reboot_button), "clicked",
                    G_CALLBACK (reboot_clicked), NULL);
}

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
    gtk_widget_set_sensitive (reboot_button, FALSE);
}

static void
set_log_dir (const char *remote_dir)
{
  CLEANUP_FREE char *msg;

  if (asprintf (&msg,
                _("Log files and debug information "
                  "is saved to this directory "
                  "on the conversion server:\n"
                  "%s"),
                remote_dir ? remote_dir : "") == -1) {
    perror ("asprintf");
    exit (EXIT_FAILURE);
  }

  gtk_label_set_text (GTK_LABEL (log_label), msg);
}

static void
set_status (const char *msg)
{
  gtk_label_set_text (GTK_LABEL (status_label), msg);
}

/* Append output from the virt-v2v process to the buffer, and scroll
 * to ensure it is visible.
 */
static void
add_v2v_output (const char *msg)
{
  static size_t linelen = 0;
  const char *p0, *p;

  /* Gtk2 (in ~ Fedora 23) has a regression where it takes much
   * longer to display long lines, to the point where the virt-p2v
   * UI would still be slowly display kernel modules while the
   * conversion had finished.  For this reason, arbitrarily break
   * long lines.
   */
  for (p0 = p = msg; *p; ++p) {
    linelen++;
    if (*p == '\n' || linelen > 1024) {
      add_v2v_output_2 (p0, p-p0+1);
      if (*p != '\n')
        add_v2v_output_2 ("\n", 1);
      linelen = 0;
      p0 = p+1;
    }
  }
  add_v2v_output_2 (p0, p-p0);
}

static void
add_v2v_output_2 (const char *msg, size_t len)
{
  GtkTextBuffer *buf;
  GtkTextIter iter;

  /* Insert it at the end. */
  buf = gtk_text_view_get_buffer (GTK_TEXT_VIEW (v2v_output));
  gtk_text_buffer_get_end_iter (buf, &iter);
  gtk_text_buffer_insert (buf, &iter, msg, len);

  /* Scroll to the end of the buffer. */
  gtk_text_buffer_get_end_iter (buf, &iter);
  gtk_text_view_scroll_to_iter (GTK_TEXT_VIEW (v2v_output), &iter,
                                0, FALSE, 0., 1.);
}

/* User clicked the Start conversion button. */
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

  config->verbose =
    gtk_toggle_button_get_active (GTK_TOGGLE_BUTTON (debug_button));

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
  free (config->output);
  config->output =
    gtk_combo_box_text_get_active_text (GTK_COMBO_BOX_TEXT (o_combo));

  config->output_allocation = OUTPUT_ALLOCATION_NONE;
  str2 = gtk_combo_box_text_get_active_text (GTK_COMBO_BOX_TEXT (oa_combo));
  if (str2) {
    if (STREQ (str2, "sparse"))
      config->output_allocation = OUTPUT_ALLOCATION_SPARSE;
    else if (STREQ (str2, "preallocated"))
      config->output_allocation = OUTPUT_ALLOCATION_PREALLOCATED;
    free (str2);
  }

  free (config->output_connection);
  str = gtk_entry_get_text (GTK_ENTRY (oc_entry));
  if (str && STRNEQ (str, ""))
    config->output_connection = strdup (str);
  else
    config->output_connection = NULL;

  free (config->output_format);
  str = gtk_entry_get_text (GTK_ENTRY (of_entry));
  if (str && STRNEQ (str, ""))
    config->output_format = strdup (str);
  else
    config->output_format = NULL;

  free (config->output_storage);
  str = gtk_entry_get_text (GTK_ENTRY (os_entry));
  if (str && STRNEQ (str, ""))
    config->output_storage = strdup (str);
  else
    config->output_storage = NULL;

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
  if (err != 0) {
    fprintf (stderr, "pthread_create: %s\n", strerror (err));
    exit (EXIT_FAILURE);
  }
  pthread_attr_destroy (&attr);
}

static void *
start_conversion_thread (void *data)
{
  struct config *copy = data;
  int r;
  GtkWidget *dlg;

  r = start_conversion (copy, notify_ui_callback);
  free_config (copy);

  gdk_threads_enter ();

  if (r == -1) {
    const char *err = get_conversion_error ();

    dlg = gtk_message_dialog_new (GTK_WINDOW (run_dlg),
                                  GTK_DIALOG_DESTROY_WITH_PARENT,
                                  GTK_MESSAGE_ERROR,
                                  GTK_BUTTONS_OK,
                                  _("Conversion failed: %s"), err);
    gtk_window_set_title (GTK_WINDOW (dlg), _("Conversion failed"));
    gtk_dialog_run (GTK_DIALOG (dlg));
    gtk_widget_destroy (dlg);
  }
  else {
    dlg = gtk_message_dialog_new (GTK_WINDOW (run_dlg),
                                  GTK_DIALOG_DESTROY_WITH_PARENT,
                                  GTK_MESSAGE_INFO,
                                  GTK_BUTTONS_OK,
                                  _("The conversion was successful."));
    gtk_window_set_title (GTK_WINDOW (dlg), _("Conversion was successful"));
    gtk_dialog_run (GTK_DIALOG (dlg));
    gtk_widget_destroy (dlg);
  }

  /* Disable the cancel button. */
  gtk_widget_set_sensitive (cancel_button, FALSE);

  /* Enable the reboot button. */
  if (is_iso_environment)
    gtk_widget_set_sensitive (reboot_button, TRUE);

  gdk_threads_leave ();

  /* Thread is detached anyway, so no one is waiting for the status. */
  return NULL;
}

static void
notify_ui_callback (int type, const char *data)
{
  gdk_threads_enter ();

  switch (type) {
  case NOTIFY_LOG_DIR:
    set_log_dir (data);
    break;

  case NOTIFY_REMOTE_MESSAGE:
    add_v2v_output (data);
    break;

  case NOTIFY_STATUS:
    set_status (data);
    break;

  default:
    fprintf (stderr,
             "%s: unknown message during conversion: type=%d data=%s\n",
             guestfs_int_program_name, type, data);
  }

  gdk_threads_leave ();
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

static void
cancel_conversion_clicked (GtkWidget *w, gpointer data)
{
  /* This makes start_conversion return an error (eventually). */
  cancel_conversion ();
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
