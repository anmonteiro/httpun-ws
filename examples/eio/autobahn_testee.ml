let connection_handler ~sw :
    Eio.Net.Sockaddr.stream -> _ Eio.Net.stream_socket -> unit =
  let websocket_handler _client_address wsd =
    let fragmented_message :
        ([ `Text | `Binary ] * Bytes.t list * int) option ref
      =
      ref None
    in
    let schedule_read_all payload k =
      let chunks = Buffer.create 256 in
      let rec on_read bs ~off ~len =
        Buffer.add_string chunks (Bigstringaf.substring bs ~off ~len);
        Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
      and on_eof () = k (Buffer.contents chunks) in
      Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
    in
    let schedule_read_chunks payload k =
      let rev_chunks = ref [] in
      let total_len = ref 0 in
      let rec on_read bs ~off ~len =
        let chunk = Bytes.create len in
        Bigstringaf.blit_to_bytes bs ~src_off:off chunk ~dst_off:0 ~len;
        rev_chunks := chunk :: !rev_chunks;
        total_len := !total_len + len;
        Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
      and on_eof () = k !rev_chunks !total_len in
      Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
    in
    let send_bytes (kind : [ `Text | `Binary ]) rev_chunks total_len =
      let bytes =
        match total_len with
        | 0 -> Bytes.empty
        | _ ->
          let bytes = Bytes.create total_len in
          let off = ref 0 in
          List.iter
            (fun chunk ->
              let len = Bytes.length chunk in
              Bytes.blit chunk 0 bytes !off len;
              off := !off + len)
            (List.rev rev_chunks);
          bytes
      in
      Httpun_ws.Wsd.send_bytes wsd ~is_fin:true
        ~kind:(kind :> [ `Binary | `Continuation | `Text ])
        bytes ~off:0 ~len:total_len
    in
    let close_with_payload payload =
      schedule_read_all payload @@ fun raw ->
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
    let pong payload =
      schedule_read_all payload @@ fun data ->
        let application_data =
          match String.length data with
          | 0 -> None
          | len ->
            let buffer = Bigstringaf.create len in
            Bigstringaf.blit_from_string data ~src_off:0 buffer ~dst_off:0 ~len;
            Some Httpun.IOVec.{ buffer; off = 0; len }
        in
        Httpun_ws.Wsd.send_pong ?application_data wsd
    in
    let frame ~opcode ~is_fin ~len:_ payload =
      match (opcode : Httpun_ws.Websocket.Opcode.t) with
      | `Text ->
        schedule_read_chunks payload @@ fun chunks total_len ->
        if is_fin
        then send_bytes `Text chunks total_len
        else fragmented_message := Some (`Text, chunks, total_len)
      | `Binary ->
        schedule_read_chunks payload @@ fun chunks total_len ->
        if is_fin
        then send_bytes `Binary chunks total_len
        else fragmented_message := Some (`Binary, chunks, total_len)
      | `Continuation ->
        schedule_read_chunks payload @@ fun rev_chunks total_len ->
        begin match !fragmented_message with
        | Some (kind, prev_rev_chunks, prev_total_len) ->
          let rev_chunks = rev_chunks @ prev_rev_chunks in
          let total_len = prev_total_len + total_len in
          if is_fin
          then (
            fragmented_message := None;
            send_bytes kind rev_chunks total_len)
          else fragmented_message := Some (kind, rev_chunks, total_len)
        | None -> ()
        end
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
