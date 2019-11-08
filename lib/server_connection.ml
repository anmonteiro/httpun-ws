module IOVec = Httpaf.IOVec

type ('fd, 'io) state =
  | Handshake of ('fd, 'io) Server_handshake.t
  | Websocket of Server_websocket.t

type input_handlers = Server_websocket.input_handlers =
  { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> Bigstringaf.t -> off:int -> len:int -> unit
  ; eof   : unit                                                                          -> unit }

type error = [ `Exn of exn ]

type error_handler = Wsd.t -> error -> unit

type ('fd, 'io) t =
  { mutable state: ('fd, 'io) state
  ; websocket_handler: Wsd.t -> input_handlers
  ; error_handler: error_handler
  ; wakeup_reader : (unit -> unit) list ref
  }

let is_closed t =
  match t.state with
  | Handshake handshake ->
    Server_handshake.is_closed handshake
  | Websocket websocket ->
    Server_websocket.is_closed websocket

let on_wakeup_reader t k =
  if is_closed t
  then failwith "called on_wakeup_reader on closed conn"
  else
    t.wakeup_reader := k::!(t.wakeup_reader)

let wakeup_reader t =
  let fs = !(t.wakeup_reader) in
  t.wakeup_reader := [];
  List.iter (fun f -> f ()) fs

let passes_scrutiny _headers =
  true (* XXX(andreas): missing! *)

let default_error_handler wsd (`Exn exn) =
  let message = Printexc.to_string exn in
  let payload = Bytes.of_string message in
  Wsd.send_bytes wsd ~kind:`Text payload ~off:0 ~len:(Bytes.length payload);
  Wsd.close wsd
;;

let respond_with_upgrade ?(headers=Httpaf.Headers.empty) ~sha1 reqd upgrade_handler =
  let request = Httpaf.Reqd.request reqd in
  if passes_scrutiny request.headers then begin
    let key = Httpaf.Headers.get_exn request.headers "sec-websocket-key" in
    let accept = sha1 (key ^ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") in
    let upgrade_headers = Httpaf.Headers.of_list [
      "Transfer-Encoding",    "chunked";
      "Upgrade",              "websocket";
      "Connection",           "upgrade";
      "Sec-Websocket-Accept", accept;
    ]
    in
    let headers = Httpaf.Headers.(add_list upgrade_headers (to_list headers)) in
    Ok (Httpaf.Reqd.respond_with_upgrade reqd headers upgrade_handler)
  end else
    Error "Didn't pass scrutiny"

(* TODO(anmonteiro): future is a terrible name for this *)
let create ~sha1 ~future ?(error_handler=default_error_handler) websocket_handler =
  let rec upgrade_handler _fd =
    let t = Lazy.force t in
    t.state <- Websocket (Server_websocket.create ~websocket_handler);
    wakeup_reader t;
    future
  and request_handler reqd =
    match respond_with_upgrade ?headers:None ~sha1 reqd upgrade_handler with
    | Ok () -> ()
    | Error msg ->
      let response = Httpaf.(Response.create
        ~headers:(Headers.of_list ["Connection", "close"])
        `Bad_request)
      in
      Httpaf.Reqd.respond_with_string reqd response msg
  and t = lazy
    { state = Handshake (Server_handshake.create ~request_handler)
    ; websocket_handler
    ; error_handler
    ; wakeup_reader = ref []
    }
  in
  Lazy.force t

let create_upgraded ?(error_handler=default_error_handler) ~websocket_handler =
    { state = Websocket (Server_websocket.create ~websocket_handler)
    ; websocket_handler
    ; error_handler
    ; wakeup_reader = ref []
    }

let close t =
  match t.state with
  | Handshake handshake -> Server_handshake.close handshake
  | Websocket websocket -> Server_websocket.close websocket
;;

let set_error_and_handle t error =
  begin match t.state with
  | Handshake _ ->
    (* TODO: we need to handle this properly. There was an error in the upgrade *)
    assert false
  | Websocket { wsd; _ } ->
      if not (Wsd.is_closed wsd) then begin
        t.error_handler wsd error;
        close t
      end;
  end

let report_exn t exn =
  set_error_and_handle t (`Exn exn)

let next_read_operation t =
  match t.state with
  | Handshake handshake -> Server_handshake.next_read_operation handshake
  | Websocket websocket ->
    match Server_websocket.next_read_operation websocket with
    | `Error (`Parse (_, message)) ->
      set_error_and_handle t (`Exn (Failure message)); `Close
    | (`Read | `Close) as operation -> operation
;;

let read t bs ~off ~len =
  match t.state with
  | Handshake handshake -> Server_handshake.read handshake bs ~off ~len
  | Websocket websocket -> Server_websocket.read websocket bs ~off ~len
;;

let read_eof t bs ~off ~len =
  match t.state with
  | Handshake handshake -> Server_handshake.read_eof handshake bs ~off ~len
  | Websocket websocket -> Server_websocket.read_eof websocket bs ~off ~len
;;

let yield_reader t f =
  on_wakeup_reader t f

let next_write_operation t =
  match t.state with
  | Handshake handshake -> Server_handshake.next_write_operation handshake
  | Websocket websocket -> Server_websocket.next_write_operation websocket
;;

let report_write_result t result =
  match t.state with
  | Handshake handshake -> Server_handshake.report_write_result handshake result
  | Websocket websocket -> Server_websocket.report_write_result websocket result
;;

let yield_writer t f =
  match t.state with
  | Handshake handshake -> Server_handshake.yield_writer handshake f
  | Websocket websocket -> Server_websocket.yield_writer websocket f
;;
