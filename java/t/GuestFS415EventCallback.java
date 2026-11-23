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

/* Test that event callbacks can be registered, invoked, and
 * deleted without crashes.  Exercises the NewGlobalRef and
 * DeleteGlobalRef paths in the JNI code.
 */
public class GuestFS415EventCallback
{
    static int callback_count = 0;

    static class TestCallback implements EventCallback
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

            /* Register multiple callbacks to exercise NewGlobalRef. */
            TestCallback cb1 = new TestCallback ();
            TestCallback cb2 = new TestCallback ();
            int eh1 = g.set_event_callback (cb1, GuestFS.EVENT_CLOSE);
            int eh2 = g.set_event_callback (cb2, GuestFS.EVENT_CLOSE);

            assert eh1 >= 0 : "set_event_callback returned negative handle";
            assert eh2 >= 0 : "set_event_callback returned negative handle";
            assert eh1 != eh2 : "event handles should be different";

            /* Delete one callback, keep the other. */
            g.delete_event_callback (eh1);

            /* Close should invoke the remaining callback. */
            g.close ();
            assert callback_count == 1
                : "expected 1 callback invocation, got " + callback_count;
        }
        catch (Exception exn) {
            System.err.println (exn);
            System.exit (1);
        }
    }
}
