/* Example showing how to inspect a virtual machine disk. */

package main

import (
	"fmt"
	"os"
	"libguestfs.org/guestfs"
)

func main() {
	if len(os.Args) < 2 {
		panic ("usage: inspect-vm disk.img")
	}
	disk := os.Args[1]

	g, errno := guestfs.Create ()
	if errno != nil {
		panic (fmt.Sprintf ("could not create handle: %s", errno))
	}

	/* Attach the disk image read-only to libguestfs. */
	optargs := guestfs.OptargsAdd_drive{
		Format_is_set: true,
		Format: "raw",
		Readonly_is_set: true,
		Readonly: true,
	}
	if err := g.Add_drive (disk, &optargs); err != nil {
		panic (err)
	}

	/* Run the libguestfs back-end. */
	if err := g.Launch (); err != nil {
		panic (err)
	}

	/* Ask libguestfs to inspect for operating systems. */
	roots, err := g.Inspect_os ()
	if err != nil {
		panic (err)
	}
	if len(roots) == 0 {
		panic ("inspect-vm: no operating systems found")
	}

	for _, root := range roots {
		fmt.Printf ("Root device: %s\n", root)

		/* Print basic information about the operating system. */
		s, _ := g.Inspect_get_product_name (root)
		fmt.Printf ("  Product name: %s\n", s)
		major, _ := g.Inspect_get_major_version (root)
		minor, _ := g.Inspect_get_minor_version (root)
		fmt.Printf ("  Version:      %d.%d\n", major, minor)
		s, _ = g.Inspect_get_type (root)
		fmt.Printf ("  Type:         %s\n", s)
		s, _ = g.Inspect_get_distro (root)
		fmt.Printf ("  Distro:       %s\n", s)

		/* XXX Incomplete example.  Sorting the keys by length
		 * is unnecessarily hard in golang.
		 */
	}
}
