let sha1 s =
  s
  |> Digestif.SHA1.digest_string
  |> Digestif.SHA1.to_raw_string

let connection_handler =
  let module Body = Httpaf.Body in
  let module Headers = Httpaf.Headers in
  let module Reqd = Httpaf.Reqd in
  let module Response = Httpaf.Response in
  let module Status = Httpaf.Status in

  let websocket_handler _client_address wsd =
    let frame ~opcode ~is_fin:_ ~len:_ payload =
      match (opcode: Websocketaf.Websocket.Opcode.t) with
      | #Websocketaf.Websocket.Opcode.standard_non_control as opcode ->
        Websocketaf.Payload.schedule_read payload
          ~on_eof:ignore
          ~on_read:(fun bs ~off ~len ->
          Websocketaf.Wsd.schedule wsd bs ~kind:opcode ~off ~len)
      | `Connection_close ->
        Websocketaf.Wsd.close wsd
      | `Ping ->
        Websocketaf.Wsd.send_pong wsd
      | `Pong
      | `Other _ ->
        ()
    in
    let eof () =
      Format.eprintf "EOF\n%!";
      Websocketaf.Wsd.close wsd
    in
    { Websocketaf.Server_connection.frame
    ; eof
    }
  in

  let error_handler wsd (`Exn exn) =
    let message = Printexc.to_string exn in
    let payload = Bytes.of_string message in
    Websocketaf.Wsd.send_bytes wsd ~kind:`Text payload ~off:0
      ~len:(Bytes.length payload);
    Websocketaf.Wsd.close wsd
  in
  let http_error_handler _client_address ?request:_ error handle =
    let message =
      match error with
      | `Exn exn -> Printexc.to_string exn
      | (#Status.client_error | #Status.server_error) as error -> Status.to_string error
    in
    let body = handle Headers.empty in
    Body.Writer.write_string body message;
    Body.Writer.close body
  in
  let upgrade_handler addr upgrade () =
    let ws_conn =
      Websocketaf.Server_connection.create_websocket
        ~error_handler
        (websocket_handler addr)
    in
    upgrade
      (Gluten.make (module Websocketaf.Server_connection) ws_conn)
  in
  let request_handler addr (reqd : Httpaf.Reqd.t Gluten.Reqd.t) =
    let { Gluten.Reqd.reqd; upgrade  } = reqd in
    match Websocketaf.Handshake.respond_with_upgrade ~sha1 reqd (upgrade_handler addr upgrade) with
    | Ok () -> ()
    | Error err_str ->
        let response = Response.create
        ~headers:(Httpaf.Headers.of_list ["Connection", "close"])
        `Bad_request
    in
      Reqd.respond_with_string reqd response err_str
  in
  Httpaf_lwt_unix.Server.create_connection_handler
    ?config:None
    ~request_handler
    ~error_handler:http_error_handler

let () =
  let open Lwt.Infix in

  let port = ref 8080 in
  Arg.parse
    ["-p", Arg.Set_int port, " Listening port number (8080 by default)"]
    ignore
    "Echoes websocket messages. Runs forever.";

  let listen_address = Unix.(ADDR_INET (inet_addr_loopback, !port)) in

  Lwt.async begin fun () ->
    Lwt_io.establish_server_with_client_socket
      listen_address connection_handler
    >>= fun _server ->
      Printf.printf "Listening on port %i and echoing websocket messages.\n%!" !port;
      Lwt.return_unit
  end;

  let forever, _ = Lwt.wait () in
  Lwt_main.run forever
