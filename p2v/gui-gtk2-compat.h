/* virt-p2v
 * Copyright (C) 2009-2018 Red Hat Inc.
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

/* Backwards compatibility for ancient RHEL 5 Gtk 2.10. */
#ifndef GTK_COMBO_BOX_TEXT
#define GTK_COMBO_BOX_TEXT GTK_COMBO_BOX
#define gtk_combo_box_text_new() gtk_combo_box_new_text()
#define gtk_combo_box_text_append_text(combo, text)	\
  gtk_combo_box_append_text((combo), (text))
#define gtk_combo_box_text_get_active_text(combo)	\
  gtk_combo_box_get_active_text((combo))
#endif

#if !GTK_CHECK_VERSION(2,12,0)	/* gtk < 2.12 */
#define gtk_widget_set_tooltip_markup(widget, text) /* nothing */
#endif

#if !GTK_CHECK_VERSION(2,14,0)	/* gtk < 2.14 */
#define gtk_dialog_get_content_area(dlg) ((dlg)->vbox)
#endif

#if !GTK_CHECK_VERSION(2,18,0)	/* gtk < 2.18 */
static void
gtk_cell_renderer_set_alignment (GtkCellRenderer *cell,
                                 gfloat xalign, gfloat yalign)
{
  if ((xalign != cell->xalign) || (yalign != cell->yalign)) {
    g_object_freeze_notify (G_OBJECT (cell));

    if (xalign != cell->xalign) {
      cell->xalign = xalign;
      g_object_notify (G_OBJECT (cell), "xalign");
    }

    if (yalign != cell->yalign) {
      cell->yalign = yalign;
      g_object_notify (G_OBJECT (cell), "yalign");
    }

    g_object_thaw_notify (G_OBJECT (cell));
  }
}
#endif

#if !GTK_CHECK_VERSION(2,20,0)	/* gtk < 2.20 */
typedef struct _ResponseData ResponseData;

struct _ResponseData
{
  gint response_id;
};

static void
response_data_free (gpointer data)
{
  g_slice_free (ResponseData, data);
}

static ResponseData *
get_response_data (GtkWidget *widget, gboolean create)
{
  ResponseData *ad = g_object_get_data (G_OBJECT (widget),
                                        "gtk-dialog-response-data");

  if (ad == NULL && create) {
    ad = g_slice_new (ResponseData);

    g_object_set_data_full (G_OBJECT (widget),
			    g_intern_static_string ("gtk-dialog-response-data"),
			    ad,
			    response_data_free);
  }

  return ad;
}

static GtkWidget *
gtk_dialog_get_widget_for_response (GtkDialog *dialog, gint response_id)
{
  GList *children;
  GList *tmp_list;

  children = gtk_container_get_children (GTK_CONTAINER (dialog->action_area));

  tmp_list = children;
  while (tmp_list != NULL) {
    GtkWidget *widget = tmp_list->data;
    ResponseData *rd = get_response_data (widget, FALSE);

    if (rd && rd->response_id == response_id) {
      g_list_free (children);
      return widget;
    }

    tmp_list = tmp_list->next;
  }

  g_list_free (children);

  return NULL;
}
#endif /* gtk < 2.20 */
