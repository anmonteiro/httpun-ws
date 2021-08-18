open Lwt.Infix

let websocket_handler u wsd =
  let rec input_loop wsd () =
    Lwt_io.(read_line stdin) >>= fun line ->
    let payload = Bytes.of_string line in
    Websocketaf.Wsd.send_bytes wsd ~kind:`Text payload ~off:0 ~len:(Bytes.length payload);
    if line = "exit" then begin
      Websocketaf.Wsd.close wsd;
      Lwt.return_unit
    end else
      input_loop wsd ()
  in
  Lwt.async (input_loop wsd);
  let frame ~opcode:_ ~is_fin:_ ~len:_ payload =
    Websocketaf.Payload.schedule_read payload
      ~on_eof:ignore
      ~on_read:(fun bs ~off ~len ->
    let payload = Bytes.create len in
    Lwt_bytes.blit_to_bytes
      bs off
      payload 0
      len;
    Format.printf "%s@." (Bytes.unsafe_to_string payload);)
  in
  let eof () =
    Printf.eprintf "[EOF]\n%!";
    Lwt.wakeup_later u ()
  in
  { Websocketaf.Client_connection.frame
  ; eof
  }

let error_handler = function
  | `Handshake_failure (rsp, _body) ->
    Format.eprintf "Handshake failure: %a\n%!" Httpaf.Response.pp_hum rsp
  | _ -> assert false

let () =
  let host = ref None in
  let port = ref 80 in

  Arg.parse
    ["-p", Set_int port, " Port number (80 by default)"]
    (fun host_argument -> host := Some host_argument)
    "wscat.exe [-p N] HOST";

  let host =
    match !host with
    | None -> failwith "No hostname provided"
    | Some host -> host
  in

  Lwt_main.run begin
    Lwt_unix.getaddrinfo host (string_of_int !port) [Unix.(AI_FAMILY PF_INET)]
    >>= fun addresses ->

    let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
    Lwt_unix.connect socket (List.hd addresses).Unix.ai_addr
    >>= fun () ->

    let nonce = "0123456789ABCDEF" in
    Httpaf_lwt_unix.Client.create_connection socket >>= fun conn ->
      let upgrade_request = Websocketaf.Handshake.create_request
        ~nonce
        ~headers:Httpaf.Headers.(of_list
          ["host", String.concat ":" [host; string_of_int !port]])
        "/"
      in
      let p, u = Lwt.wait () in
      let request_body = Httpaf_lwt_unix.Client.request
        conn
        ~error_handler:(fun _ -> assert false)
        ~response_handler:(fun _response _response_body ->
          let ws_conn =
            Websocketaf.Client_connection.create (websocket_handler u)
          in
          Httpaf_lwt_unix.Client.upgrade conn
            (Gluten.make (module Websocketaf.Client_connection) ws_conn))
        upgrade_request
    in
    Httpaf.Body.Writer.close request_body;
    p
  end
