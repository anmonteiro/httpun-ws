module Headers = Httpaf.Headers

type state =
  | Handshake of Client_handshake.t
  | Websocket of Websocket_connection.t

type t = { mutable state: state }

type error =
  [ Httpaf.Client_connection.error
  | `Handshake_failure of Httpaf.Response.t * Httpaf.Body.Reader.t ]

type input_handlers = Websocket_connection.input_handlers =
  { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> len:int -> Payload.t -> unit
  ; eof   : unit -> unit }

let passes_scrutiny ~status ~accept headers =
 (*
  * The client MUST validate the server's response as follows:
  *
  *   1. If the status code received from the server is not 101, the client
  *      handles the response per HTTP [RFC2616] procedures [...].
  *
  *   2. If the response lacks an |Upgrade| header field or the |Upgrade|
  *      header field contains a value that is not an ASCII case- insensitive
  *      match for the value "websocket", the client MUST _Fail the WebSocket
  *      Connection_.
  *
  *   3. If the response lacks a |Connection| header field or the |Connection|
  *      header field doesn't contain a token that is an ASCII case-insensitive
  *      match for the value "Upgrade", the client MUST _Fail the WebSocket
  *      Connection_.

  *   4. If the response lacks a |Sec-WebSocket-Accept| header field or
  *      the |Sec-WebSocket-Accept| contains a value other than the
  *      base64-encoded SHA-1 of the concatenation of the |Sec-WebSocket-
  *      Key| (as a string, not base64-decoded) with the string "258EAFA5-
  *      E914-47DA-95CA-C5AB0DC85B11" but ignoring any leading and
  *      trailing whitespace, the client MUST _Fail the WebSocket
  *      Connection_.

  * 5.  If the response includes a |Sec-WebSocket-Extensions| header
  *     field and this header field indicates the use of an extension
  *     that was not present in the client's handshake (the server has
  *     indicated an extension not requested by the client), the client
  *     MUST _Fail the WebSocket Connection_.  (The parsing of this
  *     header field to determine which extensions are requested is
  *     discussed in Section 9.1.)
  * *)
 match
   status,
   Headers.get_exn headers "upgrade",
   Headers.get_exn headers "connection",
   Headers.get_exn headers "sec-websocket-accept"
   with
   (* 1 *)
 | `Switching_protocols, upgrade, connection, sec_websocket_accept ->
   (* 2 *)
   Handshake.CI.equal upgrade "websocket" &&
   (* 3 *)
   (List.exists
     (fun v -> Handshake.CI.equal (String.trim v) "upgrade")
     (String.split_on_char ',' connection)) &&
   (* 4 *)
   String.equal sec_websocket_accept accept
   (* TODO(anmonteiro): 5 *)
  | _ -> false
  | exception _ -> false
;;

let handshake_exn t =
  match t.state with
  | Handshake handshake -> handshake
  | Websocket _ -> assert false

let connect
    ~nonce
    ?(headers = Httpaf.Headers.empty)
    ~sha1
    ~error_handler
    ~websocket_handler
    target
  =
  let rec response_handler response response_body =
    let { Httpaf.Response.status; headers; _  } = response in
    let t = Lazy.force t in
    let nonce = Base64.encode_exn nonce in
    let accept = Handshake.sec_websocket_key_proof ~sha1 nonce in
    if passes_scrutiny ~status ~accept headers then begin
      Httpaf.Body.Reader.close response_body;
      let handshake = handshake_exn t in
      t.state <-
        Websocket
         (Websocket_connection.create
          ~mode:(`Client Websocket_connection.random_int32)
          websocket_handler);
      Client_handshake.close handshake
    end else
      error_handler (`Handshake_failure(response, response_body))

  and t = lazy
    { state = Handshake (Client_handshake.create
        ~nonce
        ~headers
        ~error_handler:(error_handler :> Httpaf.Client_connection.error_handler)
        ~response_handler
        target) }
  in
  Lazy.force t

let create ?error_handler websocket_handler =
  { state =
      Websocket
        (Websocket_connection.create
          ~mode:(`Client Websocket_connection.random_int32)
          ?error_handler
          websocket_handler) }

let next_read_operation t =
  match t.state with
  | Handshake handshake -> Client_handshake.next_read_operation handshake
  | Websocket websocket ->
    match Websocket_connection.next_read_operation websocket with
    | `Error (`Parse (_, _message)) ->
        (* TODO(anmonteiro): handle this *)
        assert false
        (* set_error_and_handle t (`Exn (Failure message)); `Close *)
    | (`Read | `Close) as operation -> operation

let read t bs ~off ~len =
  match t.state with
  | Handshake handshake -> Client_handshake.read handshake bs ~off ~len
  | Websocket websocket -> Websocket_connection.read websocket bs ~off ~len

let read_eof t bs ~off ~len =
  match t.state with
  | Handshake handshake -> Client_handshake.read handshake bs ~off ~len
  | Websocket websocket -> Websocket_connection.read_eof websocket bs ~off ~len

let next_write_operation t =
  match t.state with
  | Handshake handshake -> Client_handshake.next_write_operation handshake
  | Websocket websocket -> Websocket_connection.next_write_operation websocket

let report_write_result t result =
  match t.state with
  | Handshake handshake -> Client_handshake.report_write_result handshake result
  | Websocket websocket -> Websocket_connection.report_write_result websocket result

let report_exn t exn =
  begin match t.state with
  | Handshake handshake -> Client_handshake.report_exn handshake exn
  | Websocket websocket -> Websocket_connection.report_exn websocket exn
  end

let yield_reader t f =
  match t.state with
  | Handshake handshake -> Client_handshake.yield_reader handshake f
  | Websocket _websocket -> assert false

let yield_writer t f =
  match t.state with
  | Handshake handshake -> Client_handshake.yield_writer handshake f
  | Websocket websocket -> Websocket_connection.yield_writer websocket f


let is_closed t =
  match t.state with
  | Handshake handshake -> Client_handshake.is_closed handshake
  | Websocket websocket -> Websocket_connection.is_closed websocket

let shutdown t =
  match t.state with
  | Handshake handshake -> Client_handshake.close handshake
  | Websocket websocket -> Websocket_connection.shutdown websocket
;;
