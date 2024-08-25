module IOVec = Httpun.IOVec
module Reader = Parse.Reader

type error = [ `Exn of exn ]

type error_handler = Wsd.t -> error -> unit

type frame_handler =
    opcode:Websocket.Opcode.t
    -> is_fin:bool
    -> len:int
    -> Payload.t
    -> unit

type t =
  { reader : [`Parse of string list * string] Reader.t
  ; wsd    : Wsd.t
  ; frame_handler : frame_handler
  ; eof : ?error:error -> unit -> unit
  ; frame_queue: (Parse.t * Payload.t) Queue.t
  }

type input_handlers =
  { frame : frame_handler
  ; eof : ?error:error -> unit -> unit }

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

let wakeup_reader t = Reader.wakeup t.reader

let create ~mode websocket_handler =
  let wsd = Wsd.create mode in
  let { frame = frame_handler; eof } = websocket_handler wsd in
  let frame_queue = Queue.create () in
  let handler frame payload =
    let call_handler = Queue.is_empty frame_queue in

    Queue.push (frame, payload) frame_queue;
    if call_handler
    then
      let { Parse.opcode; is_fin; payload_length; _ } = frame in
      frame_handler ~opcode ~is_fin ~len:payload_length payload
  in
  let rec reader = lazy (Reader.create handler)
  and t = lazy
    { reader = Lazy.force reader
    ; wsd
    ; frame_handler
    ; eof
    ; frame_queue
    }
  in
  Lazy.force t

let shutdown_reader t =
  Reader.force_close t.reader;
  wakeup_reader t

let shutdown t =
  shutdown_reader t;
  Wsd.close t.wsd

let set_error_and_handle t error =
  Wsd.report_error t.wsd error t.eof;
  shutdown t

let advance_frame_queue t =
  ignore (Queue.take t.frame_queue);
  if not (Queue.is_empty t.frame_queue)
  then
    let { Parse.opcode; is_fin; payload_length; _ }, payload = Queue.peek t.frame_queue in
    t.frame_handler ~opcode ~is_fin ~len:payload_length payload
;;

let rec _next_read_operation t =
  begin match Queue.peek t.frame_queue with
  | _, payload ->
    begin match Payload.input_state payload with
    | Wait ->
      begin match Reader.next t.reader with
      | (`Error _ | `Close) as operation -> operation
      | _ -> `Yield
      end
    | Ready -> Reader.next t.reader
    | Complete ->
      (* Don't advance the request queue if in an error state. *)
      begin match Reader.next t.reader with
      | `Error _ as op ->
        (* we just don't advance the request queue in the case of a parser
          error. *)
        op
      | `Read as op ->
        (* Keep reading when in a "partial" state (`Read). *)
        advance_frame_queue t;
        op
      | `Close ->
        advance_frame_queue t;
        _next_read_operation t
      end
    end;
  | exception Queue.Empty ->
    let next = Reader.next t.reader in
    begin match next with
    | `Error _ ->
      (* Don't tear down the whole connection if we saw an unrecoverable
       * parsing error, as we might be in the process of streaming back the
       * error response body to the client. *)
      shutdown_reader t
    | `Close -> ()
    | _ -> ()
    end;
    next
  end

let next_read_operation t =
  match _next_read_operation t with
  | `Error (`Parse (_, message)) ->
    set_error_and_handle t (`Exn (Failure message));
    `Close
  | `Read -> `Read
  | (`Yield | `Close) as operation -> operation

let next_write_operation t =
  Wsd.next t.wsd

let report_exn t exn =
  set_error_and_handle t (`Exn exn)

let read_with_more t bs ~off ~len more =
  let consumed = Reader.read_with_more t.reader bs ~off ~len more in
  if not (Queue.is_empty t.frame_queue)
  then (
    let _, payload = Queue.peek t.frame_queue in
    if Payload.has_pending_output payload
    then try Payload.execute_read payload
    with exn -> report_exn t exn
  );
  consumed
;;

let read t bs ~off ~len =
  read_with_more t bs ~off ~len Incomplete

let read_eof t bs ~off ~len =
  let r = read_with_more t bs ~off ~len Complete in
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

let yield_reader t k =
  if Reader.is_closed t.reader
  then k ()
  else Reader.on_wakeup t.reader k
