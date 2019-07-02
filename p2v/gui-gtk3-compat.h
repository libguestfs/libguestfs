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

/* Backwards compatibility for some deprecated functions in Gtk 3. */
#if !GTK_CHECK_VERSION(3,2,0)   /* gtk < 3.2 */
static gboolean
gdk_event_get_button (const GdkEvent *event, guint *button)
{
  if (event->type != GDK_BUTTON_PRESS)
    return FALSE;

  *button = ((const GdkEventButton *) event)->button;
  return TRUE;
}
#endif

#if GTK_CHECK_VERSION(3,2,0)   /* gtk >= 3.2 */
#define hbox_new(box, homogeneous, spacing)                    \
  do {                                                         \
    (box) = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, spacing); \
    if (homogeneous)                                           \
      gtk_box_set_homogeneous (GTK_BOX (box), TRUE);           \
  } while (0)
#define vbox_new(box, homogeneous, spacing)                    \
  do {                                                         \
    (box) = gtk_box_new (GTK_ORIENTATION_VERTICAL, spacing);   \
    if (homogeneous)                                           \
      gtk_box_set_homogeneous (GTK_BOX (box), TRUE);           \
  } while (0)
#else /* gtk < 3.2 */
#define hbox_new(box, homogeneous, spacing)             \
  (box) = gtk_hbox_new ((homogeneous), (spacing))
#define vbox_new(box, homogeneous, spacing)             \
  (box) = gtk_vbox_new ((homogeneous), (spacing))
#endif

#if GTK_CHECK_VERSION(3,4,0)   /* gtk >= 3.4 */
/* GtkGrid is sufficiently similar to GtkTable that we can just
 * redefine these functions.
 */
#define table_new(grid, rows, columns)          \
  (grid) = gtk_grid_new ()
#define table_attach(grid, child, left, right, top, bottom, xoptions, yoptions, xpadding, ypadding) \
  do {                                                                  \
    if (((xoptions) & GTK_EXPAND) != 0)                                 \
      gtk_widget_set_hexpand ((child), TRUE);                           \
    if (((xoptions) & GTK_FILL) != 0)                                   \
      gtk_widget_set_halign ((child), GTK_ALIGN_FILL);                  \
    if (((yoptions) & GTK_EXPAND) != 0)                                 \
      gtk_widget_set_vexpand ((child), TRUE);                           \
    if (((yoptions) & GTK_FILL) != 0)                                   \
      gtk_widget_set_valign ((child), GTK_ALIGN_FILL);                  \
    set_padding ((child), (xpadding), (ypadding));                      \
    gtk_grid_attach (GTK_GRID (grid), (child),                          \
                     (left), (top), (right)-(left), (bottom)-(top));    \
  } while (0)
#else
#define table_new(table, rows, columns)                 \
  (table) = gtk_table_new ((rows), (columns), FALSE)
#define table_attach(table, child, left, right,top, bottom, xoptions, yoptions, xpadding, ypadding) \
  gtk_table_attach (GTK_TABLE (table), (child),                         \
                    (left), (right), (top), (bottom),                   \
                    (xoptions), (yoptions), (xpadding), (ypadding))
#endif

#if GTK_CHECK_VERSION(3,8,0)   /* gtk >= 3.8 */
#define scrolled_window_add_with_viewport(container, child)     \
  gtk_container_add (GTK_CONTAINER (container), child)
#else
#define scrolled_window_add_with_viewport(container, child)             \
  gtk_scrolled_window_add_with_viewport (GTK_SCROLLED_WINDOW (container), child)
#endif

#if !GTK_CHECK_VERSION(3,10,0)   /* gtk < 3.10 */
#define gdk_event_get_event_type(event) ((event)->type)
#endif

#if GTK_CHECK_VERSION(3,10,0)   /* gtk >= 3.10 */
#undef GTK_STOCK_DIALOG_WARNING
#define GTK_STOCK_DIALOG_WARNING "dialog-warning"
#define gtk_image_new_from_stock gtk_image_new_from_icon_name
#endif

#if GTK_CHECK_VERSION(3,14,0)   /* gtk >= 3.14 */
#define set_padding(widget, xpad, ypad)                               \
  do {                                                                \
    if ((xpad) != 0) {                                                \
      gtk_widget_set_margin_start ((widget), (xpad));                 \
      gtk_widget_set_margin_end ((widget), (xpad));                   \
    }                                                                 \
    if ((ypad) != 0) {                                                \
      gtk_widget_set_margin_top ((widget), (ypad));                   \
      gtk_widget_set_margin_bottom ((widget), (ypad));                \
    }                                                                 \
  } while (0)
#define set_alignment(widget, xalign, yalign)                   \
  do {                                                          \
    if ((xalign) == 0.)                                         \
      gtk_widget_set_halign ((widget), GTK_ALIGN_START);        \
    else if ((xalign) == 1.)                                    \
      gtk_widget_set_halign ((widget), GTK_ALIGN_END);          \
    else                                                        \
      gtk_widget_set_halign ((widget), GTK_ALIGN_CENTER);       \
    if ((yalign) == 0.)                                         \
      gtk_widget_set_valign ((widget), GTK_ALIGN_START);        \
    else if ((xalign) == 1.)                                    \
      gtk_widget_set_valign ((widget), GTK_ALIGN_END);          \
    else                                                        \
      gtk_widget_set_valign ((widget), GTK_ALIGN_CENTER);       \
  } while (0)
#else  /* gtk < 3.14 */
#define set_padding(widget, xpad, ypad)                 \
  gtk_misc_set_padding(GTK_MISC(widget),(xpad),(ypad))
#define set_alignment(widget, xalign, yalign)                   \
  gtk_misc_set_alignment(GTK_MISC(widget),(xalign),(yalign))
#endif
