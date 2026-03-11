let connection_handler ~sw :
    Eio.Net.Sockaddr.stream -> _ Eio.Net.stream_socket -> unit =
  let websocket_handler _client_address wsd =
    let close_with_payload payload =
      let bytes = Buffer.create 16 in
      let rec on_read bs ~off ~len =
        Buffer.add_string bytes (Bigstringaf.substring bs ~off ~len);
        Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
      and on_eof () =
        let raw = Buffer.contents bytes in
        let code =
          match String.length raw with
          | 0 -> None
          | 1 -> Some `Protocol_error
          | _ ->
            let bs = Bigstringaf.of_string ~off:0 ~len:(String.length raw) raw in
            begin match Httpun_ws.Websocket.Close_code.of_bigstring bs ~off:0 with
            | Some code -> Some code
            | None -> Some `Protocol_error
            end
        in
        Httpun_ws.Wsd.close ?code wsd
      in
      Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
    in
    let pong payload =
      let chunks = ref [] in
      let total_len = ref 0 in
      let rec on_read bs ~off ~len =
        chunks := Bigstringaf.substring bs ~off ~len :: !chunks;
        total_len := !total_len + len;
        Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
      and on_eof () =
        let application_data =
          match !total_len with
          | 0 -> None
          | len ->
            let buffer = Bigstringaf.create len in
            let off = ref 0 in
            List.iter
              (fun chunk ->
                Bigstringaf.blit_from_string chunk ~src_off:0 buffer
                  ~dst_off:!off ~len:(String.length chunk);
                off := !off + String.length chunk)
              (List.rev !chunks);
            Some Httpun.IOVec.{ buffer; off = 0; len }
        in
        Httpun_ws.Wsd.send_pong ?application_data wsd
      in
      Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
    in
    let frame ~opcode ~is_fin ~len:_ payload =
      match (opcode : Httpun_ws.Websocket.Opcode.t) with
      | #Httpun_ws.Websocket.Opcode.standard_non_control as kind ->
        let chunks = Buffer.create 16 in
        let rec on_read bs ~off ~len =
          Buffer.add_string chunks (Bigstringaf.substring bs ~off ~len);
          Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
        and on_eof () =
          let data = Buffer.contents chunks in
          let payload = Bytes.of_string data in
          Httpun_ws.Wsd.send_bytes wsd ~is_fin ~kind payload ~off:0
            ~len:(Bytes.length payload)
        in
        Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
      | `Connection_close -> close_with_payload payload
      | `Ping -> pong payload
      | `Pong
      | `Other _ -> ()
    in
    let eof ?error () =
      match error with
      | Some _ -> Httpun_ws.Wsd.close ~code:`Protocol_error wsd
      | None -> Httpun_ws.Wsd.close wsd
    in
    { Httpun_ws.Websocket_connection.frame; eof }
  in
  Httpun_ws_eio.Server.create_connection_handler ?config:None ~sw websocket_handler

let () =
  let port = ref 9001 in
  Arg.parse
    [ "-p", Arg.Set_int port, " Listening port number (9001 by default)" ]
    ignore
    "Autobahn WebSocket testee for the Eio backend.";

  let listen_address = `Tcp (Eio.Net.Ipaddr.V4.loopback, !port) in
  Eio_main.run (fun env ->
      let network = Eio.Stdenv.net env in
      Eio.Switch.run (fun sw ->
          let socket =
            Eio.Net.listen ~reuse_addr:true ~reuse_port:true ~backlog:128 ~sw
              network listen_address
          in
          let domain_mgr = Eio.Stdenv.domain_mgr env in
          let never, _ = Eio.Promise.create () in
          for _ = 1 to Domain.recommended_domain_count () do
            Eio.Fiber.fork_daemon ~sw (fun () ->
                Eio.Domain_manager.run domain_mgr (fun () ->
                    Eio.Switch.run (fun sw ->
                        while true do
                          Eio.Net.accept_fork socket ~sw ~on_error:raise
                            (fun client_sock client_addr ->
                              connection_handler ~sw client_addr client_sock)
                        done;
                        `Stop_daemon)))
          done;
          Eio.Promise.await never))
