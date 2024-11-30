module IOVec = Httpun.IOVec
module Server_handshake = Gluten.Server

type state =
  | Handshake of Server_handshake.t
  | Websocket of Websocket_connection.t

type error = Websocket_connection.error
type error_handler = Websocket_connection.error_handler

type t =
  { mutable state : state
  ; websocket_handler : Wsd.t -> Websocket_connection.input_handlers
  }

let is_closed t =
  match t.state with
  | Handshake handshake -> Server_handshake.is_closed handshake
  | Websocket websocket -> Websocket_connection.is_closed websocket

let create ?config ?error_handler ~sha1 websocket_handler =
  let upgrade_handler t upgrade () =
    let ws_connection =
      Websocket_connection.create ~mode:`Server websocket_handler
    in
    t.state <- Websocket ws_connection;
    upgrade (Gluten.make (module Websocket_connection) ws_connection)
  in
  let rec request_handler { Gluten.reqd; upgrade } =
    let error msg =
      let response =
        Httpun.Response.create
          ~headers:(Httpun.Headers.of_list [ "Connection", "close" ])
          `Bad_request
      in
      Httpun.Reqd.respond_with_string reqd response msg
    in
    let ret =
      Httpun.Reqd.try_with reqd (fun () ->
        match
          Handshake.respond_with_upgrade
            ~sha1
            reqd
            (upgrade_handler (Lazy.force t) upgrade)
        with
        | Ok () -> ()
        | Error msg -> error msg)
    in
    match ret with Ok () -> () | Error exn -> error (Printexc.to_string exn)
  and t =
    lazy
      { state =
          Handshake
            (Server_handshake.create_upgradable
               ~protocol:(module Httpun.Server_connection)
               ~create:(Httpun.Server_connection.create ?config ?error_handler)
               request_handler)
      ; websocket_handler
      }
  in
  Lazy.force t

let create_websocket websocket_handler =
  { state =
      Websocket (Websocket_connection.create ~mode:`Server websocket_handler)
  ; websocket_handler
  }

let shutdown t =
  match t.state with
  | Handshake handshake -> Server_handshake.shutdown handshake
  | Websocket websocket -> Websocket_connection.shutdown websocket

let report_exn t exn =
  match t.state with
  | Handshake hs -> Server_handshake.report_exn hs exn
  | Websocket websocket -> Websocket_connection.report_exn websocket exn

let next_read_operation t =
  match t.state with
  | Handshake handshake -> Server_handshake.next_read_operation handshake
  | Websocket websocket -> Websocket_connection.next_read_operation websocket

let read t bs ~off ~len =
  match t.state with
  | Handshake handshake -> Server_handshake.read handshake bs ~off ~len
  | Websocket websocket -> Websocket_connection.read websocket bs ~off ~len

let read_eof t bs ~off ~len =
  match t.state with
  | Handshake handshake -> Server_handshake.read_eof handshake bs ~off ~len
  | Websocket websocket -> Websocket_connection.read_eof websocket bs ~off ~len

let yield_reader t f =
  match t.state with
  | Handshake handshake -> Server_handshake.yield_reader handshake f
  | Websocket websocket -> Websocket_connection.yield_reader websocket f

let next_write_operation t =
  match t.state with
  | Handshake handshake -> Server_handshake.next_write_operation handshake
  | Websocket websocket -> Websocket_connection.next_write_operation websocket

let report_write_result t result =
  match t.state with
  | Handshake handshake -> Server_handshake.report_write_result handshake result
  | Websocket websocket ->
    Websocket_connection.report_write_result websocket result

let yield_writer t f =
  match t.state with
  | Handshake handshake -> Server_handshake.yield_writer handshake f
  | Websocket websocket -> Websocket_connection.yield_writer websocket f
