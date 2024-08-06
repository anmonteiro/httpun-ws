module IOVec = Httpun.IOVec
module Reader = Parse.Reader

type error = [ `Exn of exn ]

type error_handler = Wsd.t -> error -> unit

let default_payload =
  Sys.opaque_identity (Payload.create_empty ~on_payload_eof:(fun () -> ()))

type t =
  { reader : [`Parse of string list * string] Reader.t
  ; wsd    : Wsd.t
  ; eof : unit -> unit
  ; mutable current_payload: Payload.t
  }

type input_handlers =
  { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> len:int -> Payload.t -> unit
  ; eof   : unit -> unit }

(* TODO: this should be passed as an argument from the runtime, to allow for
 * cryptographically secure random number generation. *)
(* From RFC6455§5.3:
 *   The masking key is a 32-bit value chosen at random by the client. When
 *   preparing a masked frame, the client MUST pick a fresh masking key from
 *   the set of allowed 32-bit values. The masking key needs to be
 *   unpredictable; thus, the masking key MUST be derived from a strong source
 *   of entropy, and the masking key for a given frame MUST NOT make it simple
 *   for a server/proxy to predict the masking key for a subsequent frame. *)
let random_int32 () =
  Random.int32 Int32.max_int

let default_error_handler wsd (`Exn exn) =
  let message = Printexc.to_string exn in
  let payload = Bytes.of_string message in
  Wsd.send_bytes wsd ~kind:`Text payload ~off:0 ~len:(Bytes.length payload);
  Wsd.close wsd
;;

let wakeup_reader t = Reader.wakeup t.reader

let create ~mode ?(error_handler = default_error_handler) websocket_handler =
  let wsd = Wsd.create ~error_handler mode in
  let { frame; eof } = websocket_handler wsd in
  let handler t = fun ~opcode ~is_fin ~len payload ->
    let t = Lazy.force t in
    t.current_payload <- payload;
    frame ~opcode ~is_fin ~len payload
  in
  let rec reader =
    lazy (
      Reader.create
        (fun ~opcode ~is_fin ~len payload -> (handler t ~opcode ~is_fin ~len payload))
        ~on_payload_eof:(fun () ->
          let t = Lazy.force t in
          t.current_payload <- default_payload;
        )
    )
  and t = lazy
    { reader = Lazy.force reader
    ; wsd
    ; eof
    ; current_payload = default_payload
    }
  in
  Lazy.force t

let shutdown { wsd; _ } =
  Wsd.close wsd

let set_error_and_handle t error =
  Wsd.report_error t.wsd error;
  shutdown t

let next_read_operation t =
  match Reader.next t.reader with
  | `Error (`Parse (_, message)) ->
    set_error_and_handle t (`Exn (Failure message)); `Close
  | `Read ->
    begin match t.current_payload == default_payload with
    | true -> `Read
    | false ->
      if Payload.is_read_scheduled t.current_payload
      then `Read
      else begin
        `Yield
      end
    end
  | `Close -> `Close

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
    Wsd.on_wakeup t.wsd k

let is_closed { wsd; _ } =
  Wsd.is_closed wsd

let report_exn t exn =
  set_error_and_handle t (`Exn exn)

let yield_reader t k =
  if Reader.is_closed t.reader
  then k ()
  else Reader.on_wakeup t.reader k
