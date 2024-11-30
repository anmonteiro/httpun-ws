open Core
open Async

let connection_handler :
  ([< Socket.Address.t ] as 'a) -> ([ `Active ], 'a) Socket.t -> unit Deferred.t
  =
  let module Body = Httpun.Body in
  let module Headers = Httpun.Headers in
  let module Reqd = Httpun.Reqd in
  let module Response = Httpun.Response in
  let module Status = Httpun.Status in
  let websocket_handler (_ : [< Socket.Address.t ]) wsd =
    let frame ~opcode ~is_fin:_ ~len:_ payload =
      match opcode with
      | `Continuation | `Text | `Binary ->
        Httpun_ws.Payload.schedule_read
          payload
          ~on_eof:ignore
          ~on_read:(fun bs ~off ~len ->
            Httpun_ws.Wsd.schedule wsd bs ~kind:`Text ~off ~len)
      | `Connection_close -> Httpun_ws.Wsd.close wsd
      | `Ping -> Httpun_ws.Wsd.send_ping wsd
      | `Pong | `Other _ -> ()
    in
    let eof ?error () =
      match error with
      | Some _ -> assert false
      | None ->
        Log.Global.error "EOF\n%!";
        Httpun_ws.Wsd.close wsd
    in
    { Httpun_ws.Websocket_connection.frame; eof }
  in

  Httpun_ws_async.Server.create_connection_handler
    ?config:None
    websocket_handler

let main port max_accepts_per_batch () =
  let where_to_listen = Tcp.Where_to_listen.of_port port in
  Tcp.(
    Server.create_sock
      ~on_handler_error:`Raise
      ~backlog:10_000
      ~max_connections:10_000
      ~max_accepts_per_batch
      where_to_listen)
    connection_handler
  >>= fun _server ->
  Log.Global.printf
    "Listening on port %i and echoing websocket messages.\n%!"
    port;
  Deferred.never ()

let () =
  Command.async_spec
    ~summary:"Echoes websocket messages. Runs forever."
    Command.Spec.(
      empty
      +> flag
           "-p"
           (optional_with_default 8080 int)
           ~doc:"int Source port to listen on"
      +> flag
           "-a"
           (optional_with_default 1 int)
           ~doc:"int Maximum accepts per batch")
    main
  |> Command_unix.run
