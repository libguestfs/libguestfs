/* libguestfs Java bindings
 * Copyright (C) 2014 Red Hat Inc.
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

/* Regression test for RStruct, RStructList problems.
 * https://bugzilla.redhat.com/show_bug.cgi?id=1073906
 */

import java.io.*;
import java.util.Map;
import com.redhat.et.libguestfs.*;

public class GuestFS800RHBZ1073906
{
    public static void main (String[] argv)
    {
        try {
            GuestFS g = new GuestFS ();

            PV pv = g.internal_test_rstruct ("");
            assert pv.pv_name.equals ("pv0");
            assert pv.pv_size == 0;
            assert pv.pv_fmt.equals ("unknown");
            assert pv.pv_attr.equals ("attr0");
            assert pv.pv_tags.equals ("tag0");

            PV[] pva = g.internal_test_rstructlist ("5");
            assert pva[0].pv_name.equals ("pv0");
            assert pva[0].pv_size == 0;
            assert pva[0].pv_fmt.equals ("unknown");
            assert pva[0].pv_attr.equals ("attr0");
            assert pva[0].pv_tags.equals ("tag0");
            assert pva[1].pv_name.equals ("pv1");
            assert pva[1].pv_size == 1;
            assert pva[1].pv_fmt.equals ("unknown");
            assert pva[1].pv_attr.equals ("attr1");
            assert pva[1].pv_tags.equals ("tag1");
            assert pva[2].pv_name.equals ("pv2");
            assert pva[2].pv_size == 2;
            assert pva[2].pv_fmt.equals ("unknown");
            assert pva[2].pv_attr.equals ("attr2");
            assert pva[2].pv_tags.equals ("tag2");
            assert pva[3].pv_name.equals ("pv3");
            assert pva[3].pv_size == 3;
            assert pva[3].pv_fmt.equals ("unknown");
            assert pva[3].pv_attr.equals ("attr3");
            assert pva[3].pv_tags.equals ("tag3");
            assert pva[4].pv_name.equals ("pv4");
            assert pva[4].pv_size == 4;
            assert pva[4].pv_fmt.equals ("unknown");
            assert pva[4].pv_attr.equals ("attr4");
            assert pva[4].pv_tags.equals ("tag4");

            g.close ();
        }
        catch (Exception exn) {
            System.err.println (exn);
            System.exit (1);
        }
    }
}
