let connection_handler : Unix.sockaddr -> Lwt_unix.file_descr -> unit Lwt.t =
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
    let eof () =
      Format.eprintf "EOF\n%!";
      Httpun_ws.Wsd.close wsd
    in
    { Httpun_ws.Websocket_connection.frame
    ; eof
    }
  in

  let error_handler _client_address wsd (`Exn exn) =
    let message = Printexc.to_string exn in
    let payload = Bytes.of_string message in
    Httpun_ws.Wsd.send_bytes wsd ~kind:`Text payload ~off:0
      ~len:(Bytes.length payload);
    Httpun_ws.Wsd.close wsd
  in

  Httpun_ws_lwt_unix.Server.create_connection_handler
    ?config:None
    ~websocket_handler
    ~error_handler



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
      Printf.printf "Listening on port %i and echoing websocket messages.\n" !port;
      flush stdout;
      Lwt.return_unit
  end;

  let forever, _ = Lwt.wait () in
  Lwt_main.run forever
