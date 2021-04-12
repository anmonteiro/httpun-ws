open Core
open Async

let connection_handler : ([< Socket.Address.t] as 'a) -> ([`Active], 'a) Socket.t -> unit Deferred.t =
  let module Body = Httpaf.Body in
  let module Headers = Httpaf.Headers in
  let module Reqd = Httpaf.Reqd in
  let module Response = Httpaf.Response in
  let module Status = Httpaf.Status in

  let websocket_handler _ wsd =
    let frame ~opcode ~is_fin:_ ~len:_ payload =
      match opcode with
      | `Continuation
      | `Text
      | `Binary ->
         Websocketaf.Payload.schedule_read payload
           ~on_eof:ignore
           ~on_read:(fun bs ~off ~len ->
           Websocketaf.Wsd.schedule wsd bs ~kind:`Text ~off ~len)
      | `Connection_close ->
        Websocketaf.Wsd.close wsd
      | `Ping ->
        Websocketaf.Wsd.send_ping wsd
      | `Pong
      | `Other _ ->
        ()
    in
    let eof () =
      Log.Global.error "EOF\n%!";
      Websocketaf.Wsd.close wsd
    in
    { Websocketaf.Server_connection.frame
    ; eof
    }
  in

  let error_handler _client_address wsd (`Exn exn) =
    let message = Exn.to_string exn in
    let payload = Bytes.of_string message in
    Websocketaf.Wsd.send_bytes wsd ~kind:`Text payload ~off:0
      ~len:(Bytes.length payload);
    Websocketaf.Wsd.close wsd
  in

  Websocketaf_async.Server.create_connection_handler
    ?config:None
    ~websocket_handler
    ~error_handler

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
  |> Command.run
