// Example showing how to inspect a virtual machine disk.

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import com.redhat.et.libguestfs.*;

public class InspectVM
{
    static final Comparator<String> COMPARE_KEYS_LEN =
        new Comparator<String>() {
        public int compare (String k1, String k2) {
            return k1.length() - k2.length();
        }
    };

    public static void main (String[] argv)
    {
        try {
            if (argv.length != 1)
                throw new Error ("usage: InspectVM disk.img");

            String disk = argv[0];

            GuestFS g = new GuestFS ();

            // Attach the disk image read-only to libguestfs.
            @SuppressWarnings("serial") Map<String, Object> optargs =
                new HashMap<String, Object>() {
                {
                    //put ("format", "raw");
                    put ("readonly", Boolean.TRUE);
                }
            };

            g.add_drive_opts (disk, optargs);

            // Run the libguestfs back-end.
            g.launch ();

            // Ask libguestfs to inspect for operating systems.
            String roots[] = g.inspect_os ();
            if (roots.length == 0)
                throw new Error ("inspect_vm: no operating systems found");

            for (String root : roots) {
                System.out.println ("Root device: " + root);

                // Print basic information about the operating system.
                System.out.println ("  Product name: " +
                                    g.inspect_get_product_name (root));
                System.out.println ("  Version:      " +
                                    g.inspect_get_major_version (root) +
                                    "." +
                                    g.inspect_get_minor_version (root));
                System.out.println ("  Type:         " +
                                    g.inspect_get_type (root));
                System.out.println ("  Distro:       " +
                                    g.inspect_get_distro (root));

                // Mount up the disks, like guestfish -i.
                //
                // Sort keys by length, shortest first, so that we end up
                // mounting the filesystems in the correct order.
                Map<String,String> mps = g.inspect_get_mountpoints (root);
                List<String> mps_keys = new ArrayList<String> (mps.keySet ());
                Collections.sort (mps_keys, COMPARE_KEYS_LEN);

                for (String mp : mps_keys) {
                    String dev = mps.get (mp);
                    try {
                        g.mount_ro (dev, mp);
                    }
                    catch (Exception exn) {
                        System.err.println (exn + " (ignored)");
                    }
                }

                // If /etc/issue.net file exists, print up to 3 lines.
                String filename = "/etc/issue.net";
                if (g.is_file (filename)) {
                    System.out.println ("--- " + filename + " ---");
                    String[] lines = g.head_n (3, filename);
                    for (String line : lines)
                        System.out.println (line);
                }

                // Unmount everything.
                g.umount_all ();
            }
        }
        catch (Exception exn) {
            System.err.println (exn);
            System.exit (1);
        }
    }
}
