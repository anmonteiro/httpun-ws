let connection_handler ~sw :
  Eio.Net.Sockaddr.stream -> _ Eio.Net.stream_socket -> unit
  =
  let module Body = Httpun.Body in
  let module Headers = Httpun.Headers in
  let module Reqd = Httpun.Reqd in
  let module Response = Httpun.Response in
  let module Status = Httpun.Status in
  let websocket_handler _client_address wsd =
    let frame ~opcode ~is_fin ~len payload =
      Format.eprintf
        "FRAME %a %d %B@."
        Httpun_ws.Websocket.Opcode.pp_hum
        opcode
        len
        is_fin;
      match (opcode : Httpun_ws.Websocket.Opcode.t) with
      | #Httpun_ws.Websocket.Opcode.standard_non_control as opcode ->
        let rec on_read bs ~off ~len =
          Format.eprintf
            "do it %d %S@."
            len
            (Bigstringaf.substring bs ~off ~len);
          Httpun_ws.Wsd.schedule wsd bs ~kind:opcode ~off ~len;
          Httpun_ws.Payload.schedule_read payload ~on_eof:ignore ~on_read
        in
        Httpun_ws.Payload.schedule_read payload ~on_eof:ignore ~on_read
      | `Connection_close -> Httpun_ws.Wsd.close ~code:(`Other 1005) wsd
      | `Ping -> Httpun_ws.Wsd.send_pong wsd
      | `Pong | `Other _ -> ()
    in
    let eof ?error () =
      match error with
      | Some (`Exn exn) ->
        let message = Printexc.to_string exn in
        let payload = Bytes.of_string message in
        Httpun_ws.Wsd.send_bytes
          wsd
          ~kind:`Text
          payload
          ~off:0
          ~len:(Bytes.length payload);
        Httpun_ws.Wsd.close wsd
      | None ->
        Format.eprintf "EOF\n%!";
        Httpun_ws.Wsd.close wsd
    in
    { Httpun_ws.Websocket_connection.frame; eof }
  in

  Httpun_ws_eio.Server.create_connection_handler
    ?config:None
    ~sw
    websocket_handler

let () =
  let port = ref 8080 in
  Arg.parse
    [ "-p", Arg.Set_int port, " Listening port number (8080 by default)" ]
    ignore
    "Echoes websocket messages. Runs forever.";

  let listen_address = `Tcp (Eio.Net.Ipaddr.V4.loopback, !port) in
  Eio_main.run (fun env ->
    let network = Eio.Stdenv.net env in
    Eio.Switch.run (fun sw ->
      let socket =
        Eio.Net.listen
          ~reuse_addr:true
          ~reuse_port:true
          ~backlog:5
          ~sw
          network
          listen_address
      in
      let domain_mgr = Eio.Stdenv.domain_mgr env in
      let p, _ = Eio.Promise.create () in
      for _i = 1 to Domain.recommended_domain_count () do
        Eio.Fiber.fork_daemon ~sw (fun () ->
          Eio.Domain_manager.run domain_mgr (fun () ->
            Eio.Switch.run (fun sw ->
              while true do
                Eio.Net.accept_fork
                  socket
                  ~sw
                  ~on_error:raise
                  (fun client_sock client_addr ->
                     (* let p, u = Eio.Promise.create () in *)
                     connection_handler ~sw client_addr client_sock)
              done;
              `Stop_daemon)))
      done;
      Eio.Promise.await p))
