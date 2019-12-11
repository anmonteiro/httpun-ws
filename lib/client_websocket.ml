module IOVec = Httpaf.IOVec

type t =
  { reader : [`Parse of string list * string] Reader.t
  ; wsd    : Wsd.t
  ; eof    : unit -> unit }

type input_handlers =
  { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> Bigstringaf.t -> off:int -> len:int -> unit
  ; eof   : unit -> unit }

let random_int32 () =
  Random.int32 Int32.max_int

let create ~websocket_handler =
  let mode         = `Client random_int32 in
  let wsd          = Wsd.create mode in
  let { frame; eof } = websocket_handler wsd in
  { reader = Reader.create frame
  ; wsd
  ; eof
  }

let next_read_operation t =
  Reader.next t.reader

let next_write_operation t =
  Wsd.next t.wsd

let read t bs ~off ~len =
  Reader.read_with_more t.reader bs ~off ~len Incomplete

let read_eof t bs ~off ~len =
  let r = Reader.read_with_more t.reader bs ~off ~len Complete in
  t.eof ();
  r

let report_write_result t result =
  Wsd.report_result t.wsd result

let yield_writer t k =
  if Wsd.is_closed t.wsd
  then begin
    Wsd.close t.wsd;
    k ()
  end else
    Wsd.when_ready_to_write t.wsd k

let close { wsd; _ } =
  Wsd.close wsd
