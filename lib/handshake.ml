module Headers = Httpaf.Headers

let create_request ~nonce ~headers target =
  let nonce = Base64.encode_exn nonce in
  let headers =
    Headers.add_list
      headers
      [ "upgrade"              , "websocket"
      ; "connection"           , "upgrade"
      ; "sec-websocket-version", "13"
      ; "sec-websocket-key"    , nonce
      ]
  in
  Httpaf.Request.create ~headers `GET target

let sec_websocket_key_proof ~sha1 sec_websocket_key =
  (* From RFC6455§1.3:
   *   For this header field, the server has to take the value (as present
   *   in the header field, e.g., the base64-encoded [RFC4648] version minus
   *   any leading and trailing whitespace) and concatenate this with the
   *   Globally Unique Identifier (GUID, [RFC4122]) "258EAFA5-E914-47DA-
   *   95CA-C5AB0DC85B11" in string form, which is unlikely to be used by
   *   network endpoints that do not understand the WebSocket Protocol.  A
   *   SHA-1 hash (160 bits) [FIPS.180-3], base64-encoded (see Section 4 of
   *   [RFC4648]), of this concatenation is then returned in the server's
   *   handshake. *)
  let concatenation =
   sec_websocket_key ^ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  in
  Base64.encode_exn ~pad:true (sha1 concatenation)

(* Copied from headers.ml in http/af.
 * Compares ASCII strings in a Case Insensitive manner. *)
module CI = struct
  let[@inline always] lower c =
    if c >= 0x41 && c <= 0x5a then c + 32 else c

  let equal x y =
    let len = String.length x in
    len = String.length y && (
      let equal_so_far = ref true in
      let i            = ref 0 in
      while !equal_so_far && !i < len do
        let c1 = Char.code (String.unsafe_get x !i) in
        let c2 = Char.code (String.unsafe_get y !i) in
        equal_so_far := lower c1 = lower c2;
        incr i
      done;
      !equal_so_far
    )
end

(* TODO: this function can just return the reason *)
let passes_scrutiny ~request_method headers =
  (* From RFC6455§4.2.1:
   *   The client's opening handshake consists of the following parts. If the
   *   server, while reading the handshake, finds that the client did not send
   *   a handshake that matches the description below [...], the server MUST
   *   stop processing the client's handshake and return an HTTP response with
   *   an appropriate error code (such as 400 Bad Request).
   *
   *   1. An HTTP/1.1 or higher GET request, including a "Request-URI"
   *      [RFC2616] [...].
   *
   *   2. A |Host| header field containing the server's authority.
   *
   *   3. An |Upgrade| header field containing the value "websocket", treated
   *      as an ASCII case-insensitive value.
   *
   *   4. A |Connection| header field that includes the token "Upgrade",treated
   *      as an ASCII case-insensitive value.
   *
   *   5. A |Sec-WebSocket-Key| header field with a base64-encoded (see Section
   *      4 of [RFC4648]) value that, when decoded, is 16 bytes in length.
   *
   *   6. A |Sec-WebSocket-Version| header field, with a value of 13.
   *
   *   [...]
   *
   *   Note: there are 9 points in the above section of the RFC, and the last
   *   3 refer to optional fields.
   *)
 match
   request_method,
   Headers.get_exn headers "host",
   Headers.get_exn headers "upgrade",
   Headers.get_exn headers "connection",
   Headers.get_exn headers "sec-websocket-key",
   Headers.get_exn headers "sec-websocket-version"
   with
   (* 1,   2 *)
 | `GET, _host, upgrade, connection, sec_websocket_key, "13" ->
   (* 3 *)
   CI.equal upgrade "websocket" &&
   (* 4 *)
   (List.exists
     (fun v -> CI.equal (String.trim v) "upgrade")
     (String.split_on_char ',' connection)) &&
   (* 5 *)
   (try String.length (Base64.decode_exn ~pad:true sec_websocket_key) = 16
    with | _ -> false)
 | _ -> false
 | exception _ -> false

let upgrade_headers ~sha1 ~request_method headers =
  if passes_scrutiny ~request_method headers then begin
    let sec_websocket_key = Headers.get_exn headers "sec-websocket-key" in
    let accept = sec_websocket_key_proof ~sha1 sec_websocket_key in
    let upgrade_headers =
      [ "Upgrade",              "websocket"
      ; "Connection",           "upgrade"
      ; "Sec-Websocket-Accept", accept
      ]
    in
    Ok upgrade_headers
  end else
    Error "Didn't pass scrutiny"

let respond_with_upgrade ?(headers=Headers.empty) ~sha1 reqd upgrade_handler =
  let request = Httpaf.Reqd.request reqd in
  match upgrade_headers ~sha1 ~request_method:request.meth request.headers with
  | Ok upgrade_headers ->
    Httpaf.Reqd.respond_with_upgrade reqd (Headers.add_list headers upgrade_headers) upgrade_handler;
    Ok ()
  | Error msg -> Error msg
