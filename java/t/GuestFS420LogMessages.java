/* libguestfs Java bindings
 * Copyright (C) 2013 Red Hat Inc.
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

import java.io.*;
import java.util.HashMap;
import com.redhat.et.libguestfs.*;

public class GuestFS420LogMessages
{
    static class LogEvent implements EventCallback
    {
        private int log_invoked = 0;

        public void event (long event, int eh, String buffer, long[] array)
        {
            String msg = "event=" + GuestFS.eventToString (event) + " " +
                "eh=" + eh + " ";

            if (buffer != null)
                msg += "buffer='" + buffer + "' ";

            if (array.length > 0) {
                msg += "array[" + array.length + "]={";
                for (int i = 0; i < array.length; ++i)
                    msg += " " + array[i];
                msg += " }";
            }

            System.out.println ("java event logged: " + msg);

            log_invoked++;
        }

        public int getLogInvoked ()
        {
            return log_invoked;
        }
    }

    public static void main (String[] argv)
    {
        try {
            GuestFS g = new GuestFS ();

            // Grab all messages into an event handler that just
            // prints each event.
            LogEvent le = new LogEvent ();
            g.set_event_callback (le,
                                  GuestFS.EVENT_APPLIANCE|GuestFS.EVENT_LIBRARY|
                                  GuestFS.EVENT_WARNING|GuestFS.EVENT_TRACE);

            // Now make sure we see some messages.
            g.set_trace (true);
            g.set_verbose (true);

            // Do some stuff.
            g.add_drive_ro ("/dev/null");
            g.set_autosync (true);

            g.close ();
            assert le.getLogInvoked() > 0;
        }
        catch (Exception exn) {
            System.err.println (exn);
            System.exit (1);
        }
    }
}
