module IOVec = Httpaf.IOVec
module Server_handshake = Gluten.Server

type state =
  | Handshake of Server_handshake.t
  | Websocket of Websocket_connection.t

type input_handlers = Websocket_connection.input_handlers =
  { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> len:int -> Payload.t -> unit
  ; eof   : unit -> unit }

type error = Websocket_connection.error
type error_handler = Websocket_connection.error_handler


type t =
  { mutable state: state
  ; websocket_handler: Wsd.t -> input_handlers
  }

let is_closed t =
  match t.state with
  | Handshake handshake ->
    Server_handshake.is_closed handshake
  | Websocket websocket ->
    Websocket_connection.is_closed websocket

let create ~sha1 ?error_handler websocket_handler =
  let rec upgrade_handler upgrade () =
    let t = Lazy.force t in
    let ws_connection =
      Websocket_connection.create ~mode:`Server ?error_handler websocket_handler
    in
    t.state <- Websocket ws_connection;
    upgrade (Gluten.make (module Websocket_connection) ws_connection);
  and request_handler { Gluten.reqd; upgrade } =
    let error msg =
      let response = Httpaf.(Response.create
        ~headers:(Headers.of_list ["Connection", "close"])
        `Bad_request)
      in
      Httpaf.Reqd.respond_with_string reqd response msg
    in
    let ret = Httpaf.Reqd.try_with reqd (fun () ->
      match Handshake.respond_with_upgrade ~sha1 reqd (upgrade_handler upgrade) with
      | Ok () -> ()
      | Error msg -> error msg)
    in
    match ret with
    | Ok () -> ()
    | Error exn ->
      error (Printexc.to_string exn)
  and t = lazy
    { state =
        Handshake
          (Server_handshake.create_upgradable
            ~protocol:(module Httpaf.Server_connection)
            ~create:
              (Httpaf.Server_connection.create ?config:None ?error_handler:None)
            request_handler)
    ; websocket_handler
    }
  in
  Lazy.force t

let create_websocket ?error_handler websocket_handler =
  { state =
      Websocket
        (Websocket_connection.create
           ~mode:`Server
           ?error_handler
           websocket_handler)
  ; websocket_handler
  }

let shutdown t =
  match t.state with
  | Handshake handshake -> Server_handshake.shutdown handshake
  | Websocket websocket -> Websocket_connection.shutdown websocket
;;

let report_exn t exn =
  match t.state with
  | Handshake _ ->
    (* TODO: we need to handle this properly. There was an error in the upgrade *)
    assert false
  | Websocket websocket ->
    Websocket_connection.report_exn websocket exn

let next_read_operation t =
  match t.state with
  | Handshake handshake -> Server_handshake.next_read_operation handshake
  | Websocket websocket -> Websocket_connection.next_read_operation websocket
;;

let read t bs ~off ~len =
  match t.state with
  | Handshake handshake -> Server_handshake.read handshake bs ~off ~len
  | Websocket websocket -> Websocket_connection.read websocket bs ~off ~len
;;

let read_eof t bs ~off ~len =
  match t.state with
  | Handshake handshake -> Server_handshake.read_eof handshake bs ~off ~len
  | Websocket websocket -> Websocket_connection.read_eof websocket bs ~off ~len
;;

let yield_reader t f =
  match t.state with
  | Handshake handshake -> Server_handshake.yield_reader handshake f
  | Websocket _ -> assert false

let next_write_operation t =
  match t.state with
  | Handshake handshake -> Server_handshake.next_write_operation handshake
  | Websocket websocket -> Websocket_connection.next_write_operation websocket
;;

let report_write_result t result =
  match t.state with
  | Handshake handshake -> Server_handshake.report_write_result handshake result
  | Websocket websocket -> Websocket_connection.report_write_result websocket result
;;

let yield_writer t f =
  match t.state with
  | Handshake handshake -> Server_handshake.yield_writer handshake f
  | Websocket websocket -> Websocket_connection.yield_writer websocket f
;;
