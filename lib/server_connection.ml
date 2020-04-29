module IOVec = Httpaf.IOVec
module Server_handshake = Gluten.Server

type state =
  | Handshake of Server_handshake.t
  | Websocket of Server_websocket.t

type input_handlers = Server_websocket.input_handlers =
  { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> Bigstringaf.t -> off:int -> len:int -> unit
  ; eof   : unit                                                                          -> unit }

type error = Server_websocket.error
type error_handler = Server_websocket.error_handler


type t =
  { mutable state: state
  ; websocket_handler: Wsd.t -> input_handlers
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

let create ~sha1 ?error_handler websocket_handler =
  let rec upgrade_handler upgrade () =
    let t = Lazy.force t in
    let ws_connection =
      Server_websocket.create ?error_handler ~websocket_handler in
    t.state <- Websocket ws_connection;
    upgrade (Gluten.make (module Server_websocket) ws_connection);
    wakeup_reader t
  and request_handler { Gluten.reqd; upgrade } =
    match Handshake.respond_with_upgrade ?headers:None ~sha1 reqd (upgrade_handler upgrade) with
    | Ok () -> ()
    | Error msg ->
      let response = Httpaf.(Response.create
        ~headers:(Headers.of_list ["Connection", "close"])
        `Bad_request)
      in
      Httpaf.Reqd.respond_with_string reqd response msg
  and t = lazy
    { state =
        Handshake
          (Server_handshake.create_upgradable
            ~protocol:(module Httpaf.Server_connection)
            ~create:
              (Httpaf.Server_connection.create ?config:None ?error_handler:None)
            request_handler)
    ; websocket_handler
    ; wakeup_reader = ref []
    }
  in
  Lazy.force t

let create_upgraded ?error_handler ~websocket_handler =
  { state = Websocket (Server_websocket.create ?error_handler ~websocket_handler)
    ; websocket_handler
    ; wakeup_reader = ref []
    }

let shutdown t =
  match t.state with
  | Handshake handshake -> Server_handshake.shutdown handshake
  | Websocket websocket -> Server_websocket.shutdown websocket
;;

let report_exn t exn =
  match t.state with
  | Handshake _ ->
    (* TODO: we need to handle this properly. There was an error in the upgrade *)
    assert false
  | Websocket websocket ->
    Server_websocket.report_exn websocket exn

let next_read_operation t =
  match t.state with
  | Handshake handshake -> Server_handshake.next_read_operation handshake
  | Websocket websocket -> Server_websocket.next_read_operation websocket
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
