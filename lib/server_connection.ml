module IOVec = Httpaf.IOVec

type 'fd state =
  | Uninitialized
  | Handshake of 'fd Server_handshake.t
  | Websocket of Server_websocket.t

type input_handlers = Server_websocket.input_handlers =
  { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> Bigstring.t -> off:int -> len:int -> unit
  ; eof   : unit                                                                          -> unit }

type error = [ `Exn of exn ]

type error_handler = Wsd.t -> error -> unit

type 'fd t =
  { mutable state: 'fd state
  ; websocket_handler: Wsd.t -> input_handlers
  ; error_handler: error_handler
  }

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
    let response = Httpaf.(Response.create ~headers `Switching_protocols) in
    Ok (Httpaf.Reqd.respond_with_upgrade reqd response upgrade_handler)
  end else
    Error "Didn't pass scrutiny"

let create ~sha1 ?(error_handler=default_error_handler) websocket_handler =
  let t =
    { state = Uninitialized
    ; websocket_handler
    ; error_handler
    }
  in
  let upgrade_handler _fd =
    t.state <- Websocket (Server_websocket.create ~websocket_handler)
  in
  let request_handler reqd =
    match respond_with_upgrade ?headers:None ~sha1 reqd upgrade_handler with
    | Ok () -> ()
    | Error msg ->
      let response = Httpaf.(Response.create
        ~headers:(Headers.of_list ["Connection", "close"])
        `Bad_request)
      in
      Httpaf.Reqd.respond_with_string reqd response msg
  in
  let handshake = Server_handshake.create ~request_handler in
  t.state <- Handshake handshake;
  t

let create_upgraded ?(error_handler=default_error_handler) ~websocket_handler =
    { state = Websocket (Server_websocket.create ~websocket_handler)
    ; websocket_handler
    ; error_handler
    }

let close t =
  match t.state with
  | Uninitialized       -> assert false
  | Handshake handshake -> Server_handshake.close handshake
  | Websocket websocket -> Server_websocket.close websocket
;;

let set_error_and_handle t error =
  begin match t.state with
  | Uninitialized -> assert false
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
  | Uninitialized       -> assert false
  | Handshake handshake -> Server_handshake.next_read_operation handshake
  | Websocket websocket ->
    match Server_websocket.next_read_operation websocket with
    | `Error (`Parse (_, message)) ->
      set_error_and_handle t (`Exn (Failure message)); `Close
    | (`Read | `Close) as operation -> operation
;;

let read t bs ~off ~len =
  match t.state with
  | Uninitialized       -> assert false
  | Handshake handshake -> Server_handshake.read handshake bs ~off ~len
  | Websocket websocket -> Server_websocket.read websocket bs ~off ~len
;;

let read_eof t bs ~off ~len =
  match t.state with
  | Uninitialized       -> assert false
  | Handshake handshake -> Server_handshake.read_eof handshake bs ~off ~len
  | Websocket websocket -> Server_websocket.read_eof websocket bs ~off ~len
;;

let yield_reader t f =
  match t.state with
  | Uninitialized       -> assert false
  | Handshake handshake -> Server_handshake.yield_reader handshake f
  | Websocket _         -> assert false
;;

let next_write_operation t =
  match t.state with
  | Uninitialized       -> assert false
  | Handshake handshake -> Server_handshake.next_write_operation handshake
  | Websocket websocket -> Server_websocket.next_write_operation websocket
;;

let report_write_result t result =
  match t.state with
  | Uninitialized       -> assert false
  | Handshake handshake -> Server_handshake.report_write_result handshake result
  | Websocket websocket -> Server_websocket.report_write_result websocket result
;;

let yield_writer t f =
  match t.state with
  | Uninitialized       -> assert false
  | Handshake handshake -> Server_handshake.yield_writer handshake f
  | Websocket websocket -> Server_websocket.yield_writer websocket f
;;
