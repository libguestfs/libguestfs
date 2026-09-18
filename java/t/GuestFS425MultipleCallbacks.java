/* libguestfs Java bindings
 * Copyright (C) 2026 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

import com.redhat.et.libguestfs.*;

/* Test that many callback invocations do not exhaust the JNI local
 * reference table.  Exercises the DeleteLocalRef cleanup in
 * java_callback for jbuf and jarray.
 */
public class GuestFS425MultipleCallbacks
{
    static int callback_count = 0;

    static class CountCallback implements EventCallback
    {
        public void event (long event, int eh, String buffer, long[] array)
        {
            callback_count++;
        }
    }

    public static void main (String[] argv)
    {
        try {
            GuestFS g = new GuestFS ();

            /* Register callback for trace events. */
            CountCallback cb = new CountCallback ();
            g.set_event_callback (cb, GuestFS.EVENT_TRACE);

            /* Enable tracing so every API call generates events. */
            g.set_trace (true);

            /* Generate many events to stress the local ref table.
             * Without DeleteLocalRef, this would exhaust the default
             * JNI local reference table (typically 512 entries).
             */
            for (int i = 0; i < 300; ++i)
                g.set_autosync (true);

            g.close ();
            assert callback_count > 0
                : "expected callbacks, got " + callback_count;
        }
        catch (Exception exn) {
            System.err.println (exn);
            System.exit (1);
        }
    }
}
