open Xml
open Ocamlduce.Load


let from_xml ?ns xml =
  let l = make ?ns () in
  let rec aux = function
    | Element (tag, attrs, child) ->
        start_elem l tag attrs; List.iter aux child; end_elem l ()
    | PCData s ->
        text l s in
  aux xml;
  get l

let from_file ?ns s = from_xml ?ns (parse_file s)
let from_string ?ns s = from_xml ?ns (parse_string s)
