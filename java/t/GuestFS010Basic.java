/* libguestfs Java bindings
 * Copyright (C) 2009-2012 Red Hat Inc.
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
import java.util.Map;
import com.redhat.et.libguestfs.*;

public class GuestFS010Basic
{
    public static void main (String[] argv)
    {
        try {
            // Delete any previous test file if one was left around.
            File old = new File ("test.img");
            old.delete ();

            RandomAccessFile f = new RandomAccessFile ("test.img", "rw");
            f.setLength (500 * 1024 * 1024);
            f.close ();

            GuestFS g = new GuestFS ();
            g.add_drive ("test.img");
            g.launch ();

            g.pvcreate ("/dev/sda");
            g.vgcreate ("VG", new String[] {"/dev/sda"});
            g.lvcreate ("LV1", "VG", 200);
            g.lvcreate ("LV2", "VG", 200);

            String[] lvs = g.lvs ();
            assert lvs[0].equals ("/dev/VG/LV1");
            assert lvs[1].equals ("/dev/VG/LV2");

            g.mkfs ("ext2", "/dev/VG/LV1");

            Map<String,String> m = g.list_filesystems ();
            assert m.containsKey ("/dev/VG/LV1");
            assert m.size () == 2;

            assert m.get ("/dev/VG/LV1").equals ("ext2");
            assert m.get ("/dev/VG/LV2").equals ("unknown");

            g.close ();

            File f2 = new File ("test.img");
            f2.delete ();
        }
        catch (Exception exn) {
            System.err.println (exn);
            System.exit (1);
        }
    }
}
