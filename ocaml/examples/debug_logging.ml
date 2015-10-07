(* Example showing how to enable debugging, and capture it into any
 * custom logging system.
 *)

(* Events we are interested in.  This bitmask covers all trace and
 * debug messages.
 *)
let event_bitmask = [
  Guestfs.EVENT_LIBRARY;
  Guestfs.EVENT_WARNING;
  Guestfs.EVENT_APPLIANCE;
  Guestfs.EVENT_TRACE
]

let rec main () =
  let g = new Guestfs.guestfs () in

  (* By default, debugging information is printed on stderr.  To
   * capture it somewhere else you have to set up an event handler
   * which will be called back as debug messages are generated.  To do
   * this use the event API.
   *
   * For more information see EVENTS in guestfs(3).
   *)
  ignore (g#set_event_callback message_callback event_bitmask);

  (* This is how debugging is enabled:
   *
   * Setting the 'trace' flag in the handle means that each libguestfs
   * call is logged (name, parameters, return).  This flag is useful
   * to see how libguestfs is being used by a program.
   *
   * Setting the 'verbose' flag enables a great deal of extra
   * debugging throughout the system.  This is useful if there is a
   * libguestfs error which you don't understand.
   *
   * Note that you should set the flags early on after creating the
   * handle.  In particular if you set the verbose flag after launch
   * then you won't see all messages.
   *
   * For more information see:
   * http://libguestfs.org/guestfs-faq.1.html#debugging-libguestfs
   *
   * Error messages raised by APIs are *not* debugging information,
   * and they are not affected by any of this.  You may have to log
   * them separately.
   *)
  g#set_trace true;
  g#set_verbose true;

  (* Do some operations which will generate plenty of trace and debug
   * messages.
   *)
  g#add_drive "/dev/null";
  g#launch ();
  g#close ()

(* This function is called back by libguestfs whenever a trace or
 * debug message is generated.
 *
 * For the classes of events we have registered above, 'array' and
 * 'array_len' will not be meaningful.  Only 'buf' and 'buf_len' will
 * be interesting and these will contain the trace or debug message.
 *
 * This example simply redirects these messages to syslog, but
 * obviously you could do something more advanced here.
 *)
and message_callback event event_handle buf array =
  if String.length buf > 0 then (
    let event_name = Guestfs.event_to_string [event] in
    Printf.printf "[%s] %S\n%!" event_name buf
  )

let () = main ()
