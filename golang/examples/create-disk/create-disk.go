/* Example showing how to create a disk image. */

package main

import (
	"fmt"
	"libguestfs.org/guestfs"
)

func main() {
	output := "disk.img"

	g, errno := guestfs.Create ()
	if errno != nil {
		panic (errno)
	}
	defer g.Close ()

	/* Create a raw-format sparse disk image, 512 MB in size. */
	if err := g.Disk_create (output, "raw", 512 * 1024 * 1024); err != nil {
		panic (err)
	}

	/* Set the trace flag so that we can see each libguestfs call. */
	g.Set_trace (true)

	/* Attach the disk image to libguestfs. */
	optargs := guestfs.OptargsAdd_drive{
		Format_is_set: true,
		Format: "raw",
		Readonly_is_set: true,
		Readonly: false,
	}
	if err := g.Add_drive (output, &optargs); err != nil {
		panic (err)
	}

	/* Run the libguestfs back-end. */
	if err := g.Launch (); err != nil {
		panic (err)
	}

	/* Get the list of devices.  Because we only added one drive
	 * above, we expect that this list should contain a single
	 * element.
	 */
	devices, err := g.List_devices ()
	if err != nil {
		panic (err)
	}
	if len(devices) != 1 {
		panic ("expected a single device from list-devices")
	}

	/* Partition the disk as one single MBR partition. */
	err = g.Part_disk (devices[0], "mbr")
	if err != nil {
		panic (err)
	}

	/* Get the list of partitions.  We expect a single element, which
	 * is the partition we have just created.
	 */
	partitions, err := g.List_partitions ()
	if err != nil {
		panic (err)
	}
	if len(partitions) != 1 {
		panic ("expected a single partition from list-partitions")
	}

	/* Create a filesystem on the partition. */
	err = g.Mkfs ("ext4", partitions[0], nil)
	if err != nil {
		panic (err)
	}

	/* Now mount the filesystem so that we can add files. */
	err = g.Mount (partitions[0], "/")
	if err != nil {
		panic (err)
	}

	/* Create some files and directories. */
	err = g.Touch ("/empty")
	if err != nil {
		panic (err)
	}
	message := []byte("Hello, world\n")
	err = g.Write ("/hello", message)
	if err != nil {
		panic (err)
	}
	err = g.Mkdir ("/foo")
	if err != nil {
		panic (err)
	}

	/* This one uploads the local file /etc/resolv.conf into
	 * the disk image.
	 */
	err = g.Upload ("/etc/resolv.conf", "/foo/resolv.conf")
	if err != nil {
		panic (err)
	}

	/* Because we wrote to the disk and we want to detect write
	 * errors, call g:shutdown.  You don't need to do this:
	 * g.Close will do it implicitly.
	 */
	if err = g.Shutdown (); err != nil {
		panic (fmt.Sprintf ("write to disk failed: %s", err))
	}
}
