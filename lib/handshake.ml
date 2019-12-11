
let create_request ~nonce ~headers target =
  let headers =
    Httpaf.Headers.add_list
      headers
      [ "upgrade"              , "websocket"
      ; "connection"           , "upgrade"
      ; "sec-websocket-version", "13"
      ; "sec-websocket-key"    , nonce
      ]
  in
  Httpaf.Request.create ~headers `GET target

let create_response_headers ~sha1 ~sec_websocket_key ~headers =
  let accept = sha1 (sec_websocket_key ^ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") in
  let upgrade_headers = [
    "Upgrade",              "websocket";
    "Connection",           "upgrade";
    "Sec-Websocket-Accept", accept;
  ]
  in
  Httpaf.Headers.add_list headers upgrade_headers
