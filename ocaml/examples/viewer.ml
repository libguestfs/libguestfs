(* This is a virtual machine graphical viewer tool.
 * Written by Richard W.M. Jones, Sept. 2009.
 *
 * It demonstrates some complex programming techniques: OCaml, Gtk+,
 * threads, and use of both libguestfs and libvirt from threads.
 *
 * You will need the following installed in order to compile it:
 *   - ocaml (http://caml.inria.fr/)
 *   - ocamlfind (http://projects.camlcity.org/projects/findlib.html/)
 *   - extlib (http://code.google.com/p/ocaml-extlib/)
 *   - lablgtk2 (http://wwwfun.kurims.kyoto-u.ac.jp/soft/lsl/lablgtk.html
 *   - xml-light (http://tech.motion-twin.com/xmllight.html)
 *   - ocaml-libvirt (http://libvirt.org/ocaml)
 *   - ocaml-libguestfs
 *
 * Note that most/all of these are available as packages via Fedora,
 * Debian, Ubuntu or GODI.  You won't need to compile them from source.
 *
 * You will also need to configure libguestfs:
 *   ./configure --enable-ocaml-viewer
 *
 * All programs in the ocaml/examples subdirectory, including this
 * one, may be freely copied without any restrictions.
 *)

(* Architecturally, there is one main thread which does all the Gtk
 * calls, and one slave thread which executes all libguestfs and
 * libvirt calls.  The main thread sends commands to the slave thread,
 * which are delivered in a queue and acted on in sequence.  Responses
 * are delivered back to the main thread as commands finish.
 *
 * The commands are just OCaml objects (type: Slave.command).  The
 * queue of commands is an OCaml Queue.  The responses are sent by adding
 * idle events to the glib main loop[1].
 *
 * If a command fails, it causes the input queue to be cleared.  In
 * this case, a failure response is sent to the main loop which
 * causes the display to be reset and possibly an error message to
 * be shown.
 *
 * The global variables [conn], [dom] and [g] are the libvirt
 * connection, current domain, and libguestfs handle respectively.
 * Because these can be accessed by both threads, they are
 * protected from the main thread by access methods which
 * (a) prevent the main thread from using them unlocked, and
 * (b) prevent the main thread from doing arbitrary / long-running
 * operations on them (the main thread must send a command instead).
 *
 * [1] http://library.gnome.org/devel/gtk-faq/stable/x499.html
 *)

open Printf
open ExtList

let (//) = Filename.concat

(* Short names for commonly used modules. *)
module C = Libvirt.Connect
module Cd = Condition
module D = Libvirt.Domain
module G = Guestfs
module M = Mutex
module Q = Queue

let verbose = ref false		       (* Verbose mode. *)

let debug fs =
  let f str = if !verbose then ( prerr_string str; prerr_newline () ) in
  ksprintf f fs

(*----------------------------------------------------------------------*)
(* Slave thread.  The signature describes what operations the main
 * thread can perform, and protects the locked internals of the
 * slave thread.
 *)
module Slave : sig
  type 'a callback = 'a -> unit

  type partinfo = {
    pt_name : string;		(** device / LV name *)
    pt_size : int64;		(** in bytes *)
    pt_content : string;	(** the output of the 'file' command *)
    pt_statvfs : G.statvfs option; (** None if not mountable *)
  }

  val no_callback : 'a callback
    (** Use this as the callback if you don't want a callback. *)

  val set_failure_callback : exn callback -> unit
    (** Set the function that is called in the main thread whenever
	there is a command failure in the slave.  The command queue
	is cleared before this is sent.  [exn] is the exception
	associated with the failure. *)

  val set_busy_callback : [`Busy|`Idle] callback -> unit
    (** Set the function that is called in the main thread whenever
	the slave thread goes busy or idle. *)

  val exit_thread : unit -> unit
    (** [exit_thread ()] causes the slave thread to exit. *)

  val connect : string option -> string option callback -> unit
    (** [connect uri cb] connects to libvirt [uri], and calls [cb]
	if it completes successfully.  Any previous connection is
	automatically cleaned up and disconnected. *)

  val get_domains : string list callback -> unit
    (** [get_domains cb] gets the list of active domains from libvirt,
	and calls [cb domains] with the names of those domains. *)

  val open_domain : string -> partinfo list callback -> unit
    (** [open_domain dom cb] sets the domain [dom] as the current
	domain, and launches a libguestfs handle for it.  Any previously
	current domain and libguestfs handle is closed.  Once the
	libguestfs handle is opened (which usually takes some time),
	callback [cb] is called with the list of partitions found
	in the guest. *)

  val slave_loop : unit -> unit
    (** The slave thread's main loop, running in the slave thread. *)

end = struct
  type partinfo = {
    pt_name : string;
    pt_size : int64;
    pt_content : string;
    pt_statvfs : G.statvfs option;
  }

  (* Commands sent by the main thread to the slave thread.  When
   * [cmd] is successfully completed, [callback] will be delivered
   * (in the main thread).  If [cmd] fails, then the global error
   * callback will be delivered in the main thread.
   *)
  type command =
    | Exit_thread
    | Connect of string option * string option callback
    | Get_domains of string list callback
    | Open_domain of string * partinfo list callback
  and 'a callback = 'a -> unit

  let string_of_command = function
    | Exit_thread -> "Exit_thread"
    | Connect (None, _) -> "Connect [no uri]"
    | Connect (Some uri, _) -> "Connect " ^ uri
    | Get_domains _ -> "Get_domains"
    | Open_domain (name, _) -> "Open_domain " ^ name

  let no_callback _ = ()

  let failure_cb = ref (fun _ -> ())
  let set_failure_callback cb = failure_cb := cb

  let busy_cb = ref (fun _ -> ())
  let set_busy_callback cb = busy_cb := cb

  (* Execute a function, while holding a mutex.  If the function
   * fails, ensure we release the mutex before rethrowing the
   * exception.
   *)
  type ('a, 'b) choice = Either of 'a | Or of 'b
  let with_lock m f =
    M.lock m;
    let r = try Either (f ()) with exn -> Or exn in
    M.unlock m;
    match r with
    | Either r -> r
    | Or exn -> raise exn

  let q = Q.create ()			(* queue of commands *)
  let q_lock = M.create ()
  let q_cond = Cd.create ()

  (* Send a command message to the slave thread. *)
  let send_to_slave c =
    debug "sending to slave: %s" (string_of_command c);
    with_lock q_lock (
      fun () ->
	Q.push c q;
	Cd.signal q_cond
    )

  let exit_thread () =
    with_lock q_lock (fun () -> Q.clear q);
    send_to_slave Exit_thread

  let connect uri cb =
    send_to_slave (Connect (uri, cb))

  let get_domains cb =
    send_to_slave (Get_domains cb)

  let open_domain dom cb =
    send_to_slave (Open_domain (dom, cb))

  (* These are not protected by a mutex because we don't allow
   * any references to these objects to escape from the slave
   * thread.
   *)
  let conn = ref None			(* libvirt connection *)
  let dom = ref None			(* libvirt domain *)
  let g = ref None			(* libguestfs handle *)

  let quit = ref false

  let rec slave_loop () =
    debug "Slave.slave_loop: waiting for a command";
    let c =
      with_lock q_lock (
	fun () ->
	  while Q.is_empty q do
	    Cd.wait q_cond q_lock
	  done;
	  Q.pop q
      ) in

    (try
       debug "Slave.slave_loop: executing: %s" (string_of_command c);
       !busy_cb `Busy;
       exec_command c;
       !busy_cb `Idle;
       debug "Slave.slave_loop: command succeeded";
     with exn ->
       (* If an exception is thrown, it means the command failed.  In
	* this case we clear the command queue and deliver the failure
	* callback in the main thread.
	*)
       debug "Slave.slave_loop: command failed";

       with_lock q_lock (fun () -> Q.clear q);
       GtkThread.async !failure_cb exn
    );

    if !quit then Thread.exit ();
    slave_loop ()

  and exec_command = function
    | Exit_thread ->
	quit := true; (* quit first in case disconnect_all throws an exn *)
	disconnect_all ()

    | Connect (name, cb) ->
	disconnect_all ();
	conn := Some (C.connect_readonly ?name ());
	cb name

    | Get_domains cb ->
	let conn = Option.get !conn in
	let doms = D.get_domains conn [D.ListAll] in
	(* Only return the names, so that the libvirt objects
	 * aren't leaked outside the slave thread.
	 *)
	let doms = List.map D.get_name doms in
	cb doms

    | Open_domain (domname, cb) ->
	let conn = Option.get !conn in
	disconnect_dom ();
	dom := Some (D.lookup_by_name conn domname);
	let dom = Option.get !dom in

	(* Get the devices. *)
	let xml = D.get_xml_desc dom in
	let devs = get_devices_from_xml xml in

	(* Create the libguestfs handle and launch it. *)
	let g' = G.create () in
	List.iter (G.add_drive_ro g') devs;
	G.launch g';
	g := Some g';

	(* Get the list of partitions. *)
	let parts = Array.to_list (G.list_partitions g') in
	(* Remove any which are PVs. *)
	let pvs = Array.to_list (G.pvs g') in
	let parts = List.filter (fun part -> not (List.mem part pvs)) parts in
	let lvs = Array.to_list (G.lvs g') in
	let parts = parts @ lvs in

	let parts = List.map (
	  fun part ->
	    (* Find out the size of each partition. *)
	    let size = G.blockdev_getsize64 g' part in

	    (* Find out what's on each partition. *)
	    let content = G.file g' part in

	    (* Try to mount it. *)
	    let statvfs =
	      try
		G.mount_ro g' part "/";
		Some (G.statvfs g' "/")
	      with _ -> None in
	    G.umount_all g';

	    { pt_name = part; pt_size = size; pt_content = content;
	      pt_statvfs = statvfs }
	) parts in

	(* Call the callback. *)
	cb parts

  (* Close all libvirt/libguestfs handles. *)
  and disconnect_all () =
    disconnect_dom ();
    (match !conn with Some conn -> C.close conn | None -> ());
    conn := None

  (* Close dom and libguestfs handles. *)
  and disconnect_dom () =
    (match !g with Some g -> G.close g | None -> ());
    g := None;
    (match !dom with Some dom -> D.free dom | None -> ());
    dom := None

  (* This would be much simpler if OCaml had either a decent XPath
   * implementation, or if ocamlduce was stable enough that we
   * could rely on it being available.  So this is *not* an example
   * of either good OCaml or good programming. XXX
   *)
  and get_devices_from_xml xml =
    let xml = Xml.parse_string xml in
    let devices =
      match xml with
      | Xml.Element ("domain", _, children) ->
	  let devices =
	    List.filter_map (
	      function
	      | Xml.Element ("devices", _, devices) -> Some devices
	      | _ -> None
	    ) children in
	  List.concat devices
      | _ ->
	  failwith "get_xml_desc didn't return <domain/>" in
    let rec source_dev_of = function
      | [] -> None
      | Xml.Element ("source", attrs, _) :: rest ->
	  (try Some (List.assoc "dev" attrs)
	   with Not_found -> source_dev_of rest)
      | _ :: rest -> source_dev_of rest
    in
    let rec source_file_of = function
      | [] -> None
      | Xml.Element ("source", attrs, _) :: rest ->
	  (try Some (List.assoc "file" attrs)
	   with Not_found -> source_file_of rest)
      | _ :: rest -> source_file_of rest
    in
    let devs =
      List.filter_map (
	function
	| Xml.Element ("disk", _, children) -> source_dev_of children
	| _ -> None
      ) devices in
    let files =
      List.filter_map (
	function
	| Xml.Element ("disk", _, children) -> source_file_of children
	| _ -> None
      ) devices in
    devs @ files
end
(* End of slave thread code. *)
(*----------------------------------------------------------------------*)

(* Display state. *)
type display_state = {
  window : GWindow.window;
  vmlist_set : string list -> unit;
  throbber_set : [`Busy|`Idle] -> unit;
  da : GMisc.drawing_area;
  draw : GDraw.drawable;
  drawing_area_repaint : unit -> unit;
  set_statusbar : string -> unit;
  clear_statusbar : unit -> unit;
  pango_large_context : GPango.context_rw;
  pango_small_context : GPango.context_rw;
}

(* This is called in the main thread whenever a command fails in the
 * slave thread.  The command queue has been cleared before this is
 * called, so our job here is to reset the main window, and if
 * necessary to turn the exception into an error message.
 *)
let failure ds exn =
  debug "failure callback: %s" (Printexc.to_string exn)

(* This is called in the main thread when the slave thread transitions
 * to busy or idle.
 *)
let busy ds state = ds.throbber_set state

(* Main window and callbacks from menu etc. *)
let main_window opened_domain repaint =
  let window_title = "Virtual machine graphical viewer" in
  let window = GWindow.window ~width:800 ~height:600 ~title:window_title () in
  let vbox = GPack.vbox ~packing:window#add () in

  (* Do the menus. *)
  let menubar = GMenu.menu_bar ~packing:vbox#pack () in
  let factory = new GMenu.factory menubar in
  let accel_group = factory#accel_group in
  let connect_menu = factory#add_submenu "_Connect" in

  let factory = new GMenu.factory connect_menu ~accel_group in
  let quit_item = factory#add_item "E_xit" ~key:GdkKeysyms._Q in

  (* Quit. *)
  let quit _ = GMain.quit (); false in
  ignore (window#connect#destroy ~callback:GMain.quit);
  ignore (window#event#connect#delete ~callback:quit);
  ignore (quit_item#connect#activate
	    ~callback:(fun () -> ignore (quit ()); ()));

  (* Top status area. *)
  let hbox = GPack.hbox ~border_width:4 ~packing:vbox#pack () in
  ignore (GMisc.label ~text:"Guest: " ~packing:hbox#pack ());

  (* List of VMs. *)
  let vmcombo = GEdit.combo_box_text ~packing:hbox#pack () in
  let vmlist_set names =
    let combo, (model, column) = vmcombo in
    model#clear ();
    List.iter (
      fun name ->
	let row = model#append () in
	model#set ~row ~column name
    ) names
  in

  (* Throbber, http://faq.pygtk.org/index.py?req=show&file=faq23.037.htp *)
  let static = Throbber.static () in
  (*let animation = Throbber.animation () in*)
  let throbber =
    GMisc.image ~pixbuf:static ~packing:(hbox#pack ~from:`END) () in
  let throbber_set = function
    | `Busy -> (*throbber#set_pixbuf animation*)
	(* Workaround because no binding for GdkPixbufAnimation: *)
	let file = Filename.dirname Sys.argv.(0) // "Throbber.gif" in
	throbber#set_file file
    | `Idle -> throbber#set_pixbuf static
  in

  (* Drawing area. *)
  let da = GMisc.drawing_area ~packing:(vbox#pack ~expand:true ~fill:true) () in
  da#misc#realize ();
  let draw = new GDraw.drawable da#misc#window in
  window#set_geometry_hints ~min_size:(80,80) (da :> GObj.widget);

  (* Calling this can be used to force a redraw of the drawing area. *)
  let drawing_area_repaint () = GtkBase.Widget.queue_draw da#as_widget in

  (* Pango contexts used to draw large and small text. *)
  let pango_large_context = da#misc#create_pango_context in
  pango_large_context#set_font_description (Pango.Font.from_string "Sans 12");
  let pango_small_context = da#misc#create_pango_context in
  pango_small_context#set_font_description (Pango.Font.from_string "Sans 8");

  (* Status bar at the bottom of the screen. *)
  let set_statusbar =
    let statusbar = GMisc.statusbar ~packing:vbox#pack () in
    let context = statusbar#new_context ~name:"Standard" in
    ignore (context#push window_title);
    fun msg ->
      context#pop ();
      ignore (context#push msg)
  in
  let clear_statusbar () = set_statusbar "" in

  (* Display the window and enter Gtk+ main loop. *)
  window#show ();
  window#add_accel_group accel_group;

  (* display_state which is threaded through all the other callbacks,
   * allowing callbacks to update the window.
   *)
  let ds =
    { window = window; vmlist_set = vmlist_set; throbber_set = throbber_set;
      da = da; draw = draw; drawing_area_repaint = drawing_area_repaint;
      set_statusbar = set_statusbar; clear_statusbar = clear_statusbar;
      pango_large_context = pango_large_context;
      pango_small_context = pango_small_context; } in

  (* Set up some callbacks which require access to the display_state. *)
  ignore (
    let combo, (model, column) = vmcombo in
    combo#connect#changed
      ~callback:(
	fun () ->
	  match combo#active_iter with
	  | None -> ()
	  | Some row ->
	      let name = model#get ~row ~column in
	      ds.set_statusbar (sprintf "Opening %s ..." name);
	      Slave.open_domain name (opened_domain ds))
  );

  ignore (da#event#connect#expose ~callback:(repaint ds));

  ds

(* Partition info for the current domain, if one is loaded. *)
let parts = ref None

(* This is called in the main thread when we've connected to libvirt. *)
let rec connected ds uri =
  debug "connected callback";
  let msg =
    match uri with
    | None -> "Connected to libvirt"
    | Some uri -> sprintf "Connected to %s" uri in
  ds.set_statusbar msg;
  Slave.get_domains (got_domains ds)

(* This is called in the main thread when we've got the list of domains. *)
and got_domains ds doms =
  debug "got_domains callback: (%s)" (String.concat " " doms);
  ds.vmlist_set doms

(* This is called when we have opened a domain. *)
and opened_domain ds parts' =
  debug "opened_domain callback";
  ds.clear_statusbar ();
  parts := Some parts';
  ds.drawing_area_repaint ()

and repaint ds _ =
  (match !parts with
   | None -> ()
   | Some parts ->
       real_repaint ds parts
  );
  false

and real_repaint ds parts =
  let width, height = ds.draw#size in
  ds.draw#set_background `WHITE;
  ds.draw#set_foreground `WHITE;
  ds.draw#rectangle ~x:0 ~y:0 ~width ~height ~filled:true ();

  let sum = List.fold_left Int64.add 0L in
  let totsize = sum (List.map (fun { Slave.pt_size = size } -> size) parts) in

  let scale = (float height -. 16.) /. Int64.to_float totsize in

  (* Calculate the height in pixels of each partition, if we were to
   * display it at a true relative size.
   *)
  let parts =
    List.map (
      fun ({ Slave.pt_size = size } as part) ->
	let h = scale *. Int64.to_float size in
	(h, part)
    ) parts in

  (*
  if !verbose then (
    eprintf "real_repaint: before borrowing:\n";
    List.iter (
      fun (h, part) ->
	eprintf "%s\t%g pix\n" part.Slave.pt_name h
    ) parts
  );
  *)

  (* Now adjust the heights of small partitions so they "borrow" some
   * height from the larger partitions.
   *)
  let min_h = 32. in
  let rec borrow needed = function
    | [] -> 0., []
    | (h, part) :: parts ->
	let spare = h -. min_h in
	if spare >= needed then (
	  needed, (h -. needed, part) :: parts
	) else if spare > 0. then (
	  let needed = needed -. spare in
	  let spare', parts = borrow needed parts in
	  spare +. spare', (h -. spare, part) :: parts
	) else (
	  let spare', parts = borrow needed parts in
	  spare', (h, part) :: parts
	)
  in
  let rec loop = function
    | parts, [] -> List.rev parts
    | prev, ((h, part) :: parts) ->
	let needed = min_h -. h in
	let h, prev, parts =
	  if needed > 0. then (
	    (* Find some spare height in a succeeding partition(s). *)
	    let spare, parts = borrow needed parts in
	    (* Or if not, in a preceeding partition(s). *)
	    let spare, prev =
	      if spare = 0. then borrow needed prev else spare, prev in
	    h +. spare, prev, parts
	  ) else (
	    h, prev, parts
	  ) in
	loop (((h, part) :: prev), parts)
  in
  let parts = loop ([], parts) in

  (*
  if !verbose then (
    eprintf "real_repaint: after borrowing:\n";
    List.iter (
      fun (h, part) ->
	eprintf "%s\t%g pix\n" part.Slave.pt_name h
    ) parts
  );
  *)

  (* Calculate the proportion space used in each partition. *)
  let parts = List.map (
    fun (h, part) ->
      let used =
	match part.Slave.pt_statvfs with
	| None -> 0.
	| Some { G.bavail = bavail; blocks = blocks } ->
	    let num = Int64.to_float (Int64.sub blocks bavail) in
	    let denom = Int64.to_float blocks in
	    num /. denom in
      (h, used, part)
  ) parts in

  (* Draw it. *)
  ignore (
    List.fold_left (
      fun y (h, used, part) ->
	(* This partition occupies pixels 8+y .. 8+y+h-1 *)
	let yb = 8 + int_of_float y
	and yt = 8 + int_of_float (y +. h) in

	ds.draw#set_foreground `WHITE;
	ds.draw#rectangle ~x:8 ~y:yb ~width:(width-16) ~height:(yt-yb)
	  ~filled:true ();

	let col =
	  if used < 0.6 then `NAME "grey"
	  else if used < 0.8 then `NAME "pink"
	  else if used < 0.9 then `NAME "hot pink"
	  else `NAME "red" in
	ds.draw#set_foreground col;
	let w = int_of_float (used *. (float width -. 16.)) in
	ds.draw#rectangle ~x:8 ~y:yb ~width:w ~height:(yt-yb) ~filled:true ();

	ds.draw#set_foreground `BLACK;
	ds.draw#rectangle ~x:8 ~y:yb ~width:(width-16) ~height:(yt-yb) ();

	(* Large text - the device name. *)
	let txt = ds.pango_large_context#create_layout in
	Pango.Layout.set_text txt part.Slave.pt_name;
	let fore = `NAME "dark slate grey" in
	ds.draw#put_layout ~x:12 ~y:(yb+4) ~fore txt;

	let { Pango.height = txtheight; Pango.width = txtwidth } =
	  Pango.Layout.get_pixel_extent txt in

	(* Small text below - the content. *)
	let txt = ds.pango_small_context#create_layout in
	Pango.Layout.set_text txt part.Slave.pt_content;
	let fore = `BLACK in
	ds.draw#put_layout ~x:12 ~y:(yb+4+txtheight) ~fore txt;

	(* Small text right - size. *)
	let size =
	  match part.Slave.pt_statvfs with
	  | None -> printable_size part.Slave.pt_size
	  | Some { G.blocks = blocks; bsize = bsize } ->
	      let bytes = Int64.mul blocks bsize in
	      let pc = 100. *. used in
	      sprintf "%s (%.1f%% used)" (printable_size bytes) pc in
	let txt = ds.pango_small_context#create_layout in
	Pango.Layout.set_text txt size;
	ds.draw#put_layout ~x:(16+txtwidth) ~y:(yb+4) ~fore txt;

	(y +. h)
    ) 0. parts
  )

and printable_size bytes =
  if bytes < 16_384L then sprintf "%Ld bytes" bytes
  else if bytes < 16_777_216L then
    sprintf "%Ld KiB" (Int64.div bytes 1024L)
  else if bytes < 17_179_869_184L then
    sprintf "%Ld MiB" (Int64.div bytes 1_048_576L)
  else
    sprintf "%Ld GiB" (Int64.div bytes 1_073_741_824L)

let default_uri = ref ""

let argspec = Arg.align [
  "-verbose", Arg.Set verbose, "Verbose mode";
  "-connect", Arg.Set_string default_uri, "Connect to libvirt URI";
]

let anon_fun _ =
  failwith (sprintf "%s: unknown command line argument"
	      (Filename.basename Sys.executable_name))

let usage_msg =
  sprintf "\

%s: graphical virtual machine disk usage viewer

Options:"
    (Filename.basename Sys.executable_name)

let main () =
  Arg.parse argspec anon_fun usage_msg;

  (* Start up the slave thread. *)
  let slave = Thread.create Slave.slave_loop () in

  (* Set up the display. *)
  let ds = main_window opened_domain repaint in

  Slave.set_failure_callback (failure ds);
  Slave.set_busy_callback (busy ds);
  let uri = match !default_uri with "" -> None | s -> Some s in
  Slave.connect uri (connected ds);

  (* Run the main thread. When this returns, the application has been closed. *)
  GtkThread.main ();

  (* Tell the slave thread to exit and wait for it to do so. *)
  Slave.exit_thread ();
  Thread.join slave

let () =
  main ()
