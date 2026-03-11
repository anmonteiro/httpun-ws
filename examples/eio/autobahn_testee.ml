module Utf8 = struct
  type t =
    { mutable needed : int
    ; mutable lo : int
    ; mutable hi : int
    }

  let create () = { needed = 0; lo = 0x80; hi = 0xBF }

  let feed_bytes t bytes =
    let rec go i =
      if i = Bytes.length bytes
      then true
      else (
        let byte = Char.code (Bytes.unsafe_get bytes i) in
        if t.needed = 0
        then (
          if byte <= 0x7F
          then go (i + 1)
          else if byte >= 0xC2 && byte <= 0xDF
          then (
            t.needed <- 1;
            t.lo <- 0x80;
            t.hi <- 0xBF;
            go (i + 1))
          else if byte = 0xE0
          then (
            t.needed <- 2;
            t.lo <- 0xA0;
            t.hi <- 0xBF;
            go (i + 1))
          else if (byte >= 0xE1 && byte <= 0xEC) || (byte >= 0xEE && byte <= 0xEF)
          then (
            t.needed <- 2;
            t.lo <- 0x80;
            t.hi <- 0xBF;
            go (i + 1))
          else if byte = 0xED
          then (
            t.needed <- 2;
            t.lo <- 0x80;
            t.hi <- 0x9F;
            go (i + 1))
          else if byte = 0xF0
          then (
            t.needed <- 3;
            t.lo <- 0x90;
            t.hi <- 0xBF;
            go (i + 1))
          else if byte >= 0xF1 && byte <= 0xF3
          then (
            t.needed <- 3;
            t.lo <- 0x80;
            t.hi <- 0xBF;
            go (i + 1))
          else if byte = 0xF4
          then (
            t.needed <- 3;
            t.lo <- 0x80;
            t.hi <- 0x8F;
            go (i + 1))
          else false)
        else if byte < t.lo || byte > t.hi
        then false
        else (
          t.needed <- t.needed - 1;
          t.lo <- 0x80;
          t.hi <- 0xBF;
          go (i + 1)))
    in
    go 0

  let is_complete t = t.needed = 0
end

let build_bytes rev_chunks total_len =
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

let is_valid_close_code code =
  match code with
  | 1000 | 1001 | 1002 | 1003 | 1007 | 1008 | 1009 | 1010 | 1011 -> true
  | _ when code >= 3000 && code <= 4999 -> true
  | _ -> false

let connection_handler ~sw :
    Eio.Net.Sockaddr.stream -> _ Eio.Net.stream_socket -> unit =
  let websocket_handler _client_address wsd =
    let fragmented_message :
        [ `Text of Utf8.t * Bytes.t list * int
        | `Binary of Bytes.t list * int ]
        option
        ref
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
    let schedule_read_text payload ~validator ~is_fin ~on_valid ~on_invalid =
      let rev_chunks = ref [] in
      let total_len = ref 0 in
      let rec on_read bs ~off ~len =
        let chunk = Bytes.create len in
        Bigstringaf.blit_to_bytes bs ~src_off:off chunk ~dst_off:0 ~len;
        if Utf8.feed_bytes validator chunk
        then (
          rev_chunks := chunk :: !rev_chunks;
          total_len := !total_len + len;
          Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read)
        else on_invalid ()
      and on_eof () =
        if is_fin && not (Utf8.is_complete validator)
        then on_invalid ()
        else on_valid !rev_chunks !total_len
      in
      Httpun_ws.Payload.schedule_read payload ~on_eof ~on_read
    in
    let send_bytes (kind : [ `Text | `Binary ]) rev_chunks total_len =
      let bytes = build_bytes rev_chunks total_len in
      Httpun_ws.Wsd.send_bytes wsd ~is_fin:true
        ~kind:(kind :> [ `Binary | `Continuation | `Text ])
        bytes ~off:0 ~len:total_len
    in
    let close_with_payload payload =
      schedule_read_chunks payload @@ fun rev_chunks total_len ->
        let code =
          match total_len with
          | 0 -> Some `Normal_closure
          | 1 -> Some `Protocol_error
          | _ ->
            let bytes = build_bytes rev_chunks total_len in
            let code = Bytes.get_uint16_be bytes 0 in
            if not (is_valid_close_code code)
            then Some `Protocol_error
            else if total_len = 2
            then Some (Httpun_ws.Websocket.Close_code.of_int_exn code)
            else (
              let reason = Bytes.sub bytes 2 (total_len - 2) in
              let validator = Utf8.create () in
              if Utf8.feed_bytes validator reason && Utf8.is_complete validator
              then Some (Httpun_ws.Websocket.Close_code.of_int_exn code)
              else Some `Invalid_frame_payload_data)
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
        let validator = Utf8.create () in
        schedule_read_text payload ~validator ~is_fin
          ~on_valid:(fun chunks total_len ->
            if is_fin
            then send_bytes `Text chunks total_len
            else fragmented_message := Some (`Text (validator, chunks, total_len)))
          ~on_invalid:(fun () ->
            Httpun_ws.Wsd.close ~code:`Invalid_frame_payload_data wsd)
      | `Binary ->
        schedule_read_chunks payload @@ fun chunks total_len ->
        if is_fin
        then send_bytes `Binary chunks total_len
        else fragmented_message := Some (`Binary (chunks, total_len))
      | `Continuation ->
        begin match !fragmented_message with
        | Some (`Text (validator, prev_rev_chunks, prev_total_len)) ->
          schedule_read_text payload ~validator ~is_fin
            ~on_valid:(fun rev_chunks total_len ->
              let rev_chunks = rev_chunks @ prev_rev_chunks in
              let total_len = prev_total_len + total_len in
              if is_fin
              then (
                fragmented_message := None;
                send_bytes `Text rev_chunks total_len)
              else fragmented_message := Some (`Text (validator, rev_chunks, total_len)))
            ~on_invalid:(fun () ->
              Httpun_ws.Wsd.close ~code:`Invalid_frame_payload_data wsd)
        | Some (`Binary (prev_rev_chunks, prev_total_len)) ->
          schedule_read_chunks payload @@ fun rev_chunks total_len ->
          let rev_chunks = rev_chunks @ prev_rev_chunks in
          let total_len = prev_total_len + total_len in
          if is_fin
          then (
            fragmented_message := None;
            send_bytes `Binary rev_chunks total_len)
          else fragmented_message := Some (`Binary (rev_chunks, total_len))
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
