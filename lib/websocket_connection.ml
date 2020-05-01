module IOVec = Httpaf.IOVec

type error = [ `Exn of exn ]

type error_handler = Wsd.t -> error -> unit

type t =
  { reader : [`Parse of string list * string] Reader.t
  ; wsd    : Wsd.t
  ; eof : unit -> unit
  ; error_handler: error_handler
  }

type input_handlers =
  { frame : opcode:Websocket.Opcode.t
          -> is_fin:bool
          -> Bigstringaf.t
          -> off:int
          -> len:int
          -> unit
  ; eof   : unit -> unit }

let random_int32 () =
  Random.int32 Int32.max_int
  (* let mode         = `Client random_int32 in *)

let default_error_handler wsd (`Exn exn) =
  let message = Printexc.to_string exn in
  let payload = Bytes.of_string message in
  Wsd.send_bytes wsd ~kind:`Text payload ~off:0 ~len:(Bytes.length payload);
  Wsd.close wsd
;;

let create ~mode ?(error_handler = default_error_handler) websocket_handler =
  let wsd = Wsd.create mode in
  let { frame; eof } = websocket_handler wsd in
  { reader = Reader.create frame
  ; wsd
  ; eof
  ; error_handler
  }

let shutdown { wsd; _ } =
  Wsd.close wsd

let set_error_and_handle t error =
  if not (Wsd.is_closed t.wsd) then begin
    t.error_handler t.wsd error;
    shutdown t
  end

let next_read_operation t =
  match Reader.next t.reader with
  | `Error (`Parse (_, message)) ->
    set_error_and_handle t (`Exn (Failure message)); `Close
  | (`Read | `Close) as operation -> operation

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

let is_closed { wsd; _ } =
  Wsd.is_closed wsd

let report_exn t exn =
  set_error_and_handle t (`Exn exn)

let yield_reader _t _f = ()
