open Core
open Async

let sha1 s =
  s
  |> Digestif.SHA1.digest_string
  |> Digestif.SHA1.to_raw_string

let connection_handler =
  let module Body = Httpun.Body in
  let module Headers = Httpun.Headers in
  let module Reqd = Httpun.Reqd in
  let module Response = Httpun.Response in
  let module Status = Httpun.Status in

  let websocket_handler _client_address wsd =
    let frame ~opcode ~is_fin:_ ~len:_ payload =
      match (opcode: Httpun_ws.Websocket.Opcode.t) with
      | #Httpun_ws.Websocket.Opcode.standard_non_control as opcode ->
        Httpun_ws.Payload.schedule_read payload
          ~on_eof:ignore
          ~on_read:(fun bs ~off ~len ->
          Httpun_ws.Wsd.schedule wsd bs ~kind:opcode ~off ~len)
      | `Connection_close ->
        Httpun_ws.Wsd.close wsd
      | `Ping ->
        Httpun_ws.Wsd.send_pong wsd
      | `Pong
      | `Other _ ->
        ()
    in
    let eof ?error () =
      match error with
      | Some _ -> assert false
      | None ->
        Format.eprintf "EOF\n%!";
        Httpun_ws.Wsd.close wsd
    in
    { Httpun_ws.Websocket_connection.frame
    ; eof
    }
  in

  let http_error_handler _client_address ?request:_ error handle =
    let message =
      match error with
      | `Exn exn -> Exn.to_string exn
      | (#Status.client_error | #Status.server_error) as error -> Status.to_string error
    in
    let body = handle Headers.empty in
    Body.Writer.write_string body message;
    Body.Writer.close body
  in
  let upgrade_handler addr upgrade () =
    let ws_conn =
      Httpun_ws.Server_connection.create_websocket (websocket_handler addr)
    in
    upgrade
      (Gluten.make (module Httpun_ws.Server_connection) ws_conn)
  in
  let request_handler addr (reqd : Httpun.Reqd.t Gluten.Reqd.t) =
    let { Gluten.Reqd.reqd; upgrade  } = reqd in
    match Httpun_ws.Handshake.respond_with_upgrade ~sha1 reqd (upgrade_handler addr upgrade) with
    | Ok () -> ()
    | Error err_str ->
        let response = Response.create
        ~headers:(Httpun.Headers.of_list ["Connection", "close"])
        `Bad_request
    in
      Reqd.respond_with_string reqd response err_str
  in
  Httpun_async.Server.create_connection_handler
    ?config:None
    ~request_handler:request_handler
    ~error_handler:http_error_handler

let main port max_accepts_per_batch () =
  let where_to_listen = Tcp.Where_to_listen.of_port port in
  Tcp.(Server.create_sock ~on_handler_error:`Raise
      ~backlog:10_000 ~max_connections:10_000 ~max_accepts_per_batch where_to_listen)
    connection_handler
  >>= fun _server ->
  Log.Global.printf "Listening on port %i and echoing websocket messages.\n%!" port;
  Deferred.never ()

let () =
  Command.async_spec
    ~summary:"Echoes websocket messages. Runs forever."
    Command.Spec.(empty +>
      flag "-p" (optional_with_default 8080 int)
        ~doc:"int Source port to listen on"
      +>
      flag "-a" (optional_with_default 1 int)
        ~doc:"int Maximum accepts per batch"
    ) main
  |> Command_unix.run
