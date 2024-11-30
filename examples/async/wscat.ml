open Core
open Async

let websocket_handler wsd =
  let rec input_loop wsd () =
    Reader.read_line (Lazy.force Reader.stdin) >>= function
    | `Ok line ->
      let payload = Bytes.of_string line in
      Httpun_ws.Wsd.send_bytes
        wsd
        ~kind:`Text
        payload
        ~off:0
        ~len:(Bytes.length payload);
      if String.(line = "exit")
      then (
        Httpun_ws.Wsd.close wsd;
        Deferred.return ())
      else input_loop wsd ()
    | `Eof -> assert false
  in
  Deferred.don't_wait_for (input_loop wsd ());
  let frame ~opcode:_ ~is_fin:_ ~len:_ payload =
    Httpun_ws.Payload.schedule_read
      payload
      ~on_eof:ignore
      ~on_read:(fun bs ~off ~len ->
        let payload = Bytes.to_string (Bigstring.to_bytes ~pos:off ~len bs) in
        Log.Global.printf "%s\n%!" payload)
  in

  let eof ?error () =
    match error with
    | Some _ -> assert false
    | None -> Log.Global.error "[EOF]\n%!"
  in
  { Httpun_ws.Websocket_connection.frame; eof }

let error_handler = function
  | `Handshake_failure (rsp, _body) ->
    Format.eprintf "Handshake failure: %a\n%!" Httpun.Response.pp_hum rsp
  | _ -> assert false

let main port host () =
  let where_to_connect = Tcp.Where_to_connect.of_host_and_port { host; port } in
  Tcp.connect_sock where_to_connect >>= fun socket ->
  let nonce = "0123456789ABCDEF" in
  let resource = "/" in
  Httpun_ws_async.Client.connect
    socket
    ~nonce
    ~host
    ~port
    ~resource
    ~error_handler
    ~websocket_handler
  >>= fun () -> Deferred.never ()

let () =
  Command.async_spec
    ~summary:"Start a websocket cat client"
    Command.Spec.(
      empty
      +> flag "-p" (optional_with_default 80 int) ~doc:"int destination port"
      +> anon ("Destination Host" %: string))
    main
  |> Command_unix.run
