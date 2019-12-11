open Lwt.Infix

let sha1 s =
  s
  |> Digestif.SHA1.digest_string
  |> Digestif.SHA1.to_raw_string
  |> Base64.encode_exn ~pad:true

module Buffer : sig
  type t

  val create : int -> t

  val get : t -> f:(Bigstringaf.t -> off:int -> len:int -> int) -> int
  val put
    :  t
    -> f:(Bigstringaf.t -> off:int -> len:int -> [ `Eof | `Ok of int ] Lwt.t)
    -> [ `Eof | `Ok of int ] Lwt.t
end = struct
  type t =
    { buffer      : Bigstringaf.t
    ; mutable off : int
    ; mutable len : int }

  let create size =
    let buffer = Bigstringaf.create size in
    { buffer; off = 0; len = 0 }

  let compress t =
    if t.len = 0
    then begin
      t.off <- 0;
      t.len <- 0;
    end else if t.off > 0
    then begin
      Bigstringaf.blit t.buffer ~src_off:t.off t.buffer ~dst_off:0 ~len:t.len;
      t.off <- 0;
    end

  let get t ~f =
    let n = f t.buffer ~off:t.off ~len:t.len in
    t.off <- t.off + n;
    t.len <- t.len - n;
    if t.len = 0
    then t.off <- 0;
    n

  let put t ~f =
    compress t;
    f t.buffer ~off:(t.off + t.len) ~len:(Bigstringaf.length t.buffer - t.len)
    >|= function
      | `Eof -> `Eof
      | `Ok n as ret ->
        t.len <- t.len + n;
        ret
end

include Websocketaf_lwt_intf

module Server (Io: IO) = struct
  module Server_connection = Websocketaf.Server_connection

  let start_read_write_loops ~socket connection =
    let read_buffer = Buffer.create 0x1000 in
    let read_loop_exited, notify_read_loop_exited = Lwt.wait () in

    let rec read_loop () =
      let rec read_loop_step () =
        match Server_connection.next_read_operation connection with
        | `Read ->
          Buffer.put ~f:(Io.read socket) read_buffer >>= begin function
          | `Eof ->
            Buffer.get read_buffer ~f:(fun bigstring ~off ~len ->
              Server_connection.read_eof connection bigstring ~off ~len)
            |> ignore;
            read_loop_step ()
          | `Ok _ ->
            Buffer.get read_buffer ~f:(fun bigstring ~off ~len ->
              Server_connection.read connection bigstring ~off ~len)
            |> ignore;
            read_loop_step ()
          end

        | `Yield | `Upgrade ->
          Server_connection.yield_reader connection read_loop;
          Lwt.return_unit

        | `Close ->
          Lwt.wakeup_later notify_read_loop_exited ();
          Io.shutdown_receive socket;
          Lwt.return_unit
      in

      Lwt.async (fun () ->
        Lwt.catch
          read_loop_step
          (fun exn ->
            Server_connection.report_exn connection exn;
            Lwt.return_unit))
    in


    let writev = Io.writev socket in
    let write_loop_exited, notify_write_loop_exited = Lwt.wait () in

    let rec write_loop () =
      let rec write_loop_step () =
        match Server_connection.next_write_operation connection with
        | `Write io_vectors ->
          writev io_vectors >>= fun result ->
          Server_connection.report_write_result connection result;
          write_loop_step ()

        | `Upgrade (io_vectors, upgrade_handler) ->
          writev io_vectors >>= fun result ->
          Server_connection.report_write_result connection result;
          upgrade_handler socket >>= write_loop_step

        | `Yield ->
          Server_connection.yield_writer connection write_loop;
          Lwt.return_unit

        | `Close _ ->
          Lwt.wakeup_later notify_write_loop_exited ();
          Io.shutdown_send socket;
          Lwt.return_unit
      in

      Lwt.async (fun () ->
        Lwt.catch
          write_loop_step
          (fun exn ->
            Server_connection.report_exn connection exn;
            Lwt.return_unit))
    in

    read_loop ();
    write_loop ();
    Lwt.join [read_loop_exited; write_loop_exited] >>= fun () ->

    Io.close socket


  (* TODO: should this error handler be a websocket error handler or an HTTP
   * error handler?*)
  let create_connection_handler ?config:_ ~websocket_handler ~error_handler:_ =
    fun client_addr socket ->
      let websocket_handler = websocket_handler client_addr in
      let connection =
        Server_connection.create
          ~future:Lwt.return_unit
          ~sha1
          websocket_handler
      in
      start_read_write_loops ~socket connection

  let create_upgraded_connection_handler ?config:_ ~websocket_handler ~error_handler =
    fun client_addr socket ->
      let websocket_handler = websocket_handler client_addr in
      let connection =
        Server_connection.create_upgraded ~error_handler ~websocket_handler
      in
      start_read_write_loops ~socket connection

  let respond_with_upgrade ?headers reqd upgrade_handler =
    Lwt.return (Server_connection.respond_with_upgrade ?headers ~sha1 reqd upgrade_handler)
end

module Client (Io: IO) = struct
  module Client_connection = Websocketaf.Client_connection

  let start_read_write_loops socket connection =
    let read_buffer = Buffer.create 0x1000 in
    let read_loop_exited, notify_read_loop_exited = Lwt.wait () in

    let rec read_loop () =
      let rec read_loop_step () =
        match Client_connection.next_read_operation connection with
        | `Read ->
          Buffer.put ~f:(Io.read socket) read_buffer >>= begin function
          | `Ok _ ->
            Buffer.get read_buffer ~f:(fun bigstring ~off ~len ->
              Client_connection.read connection bigstring ~off ~len)
            |> ignore;
            read_loop_step ()
          | `Eof ->
            Buffer.get read_buffer ~f:(fun bigstring ~off ~len ->
              Client_connection.read_eof connection bigstring ~off ~len)
            |> ignore;
            read_loop_step ()
          end

        | `Yield ->
          Client_connection.yield_reader connection read_loop;
          Lwt.return_unit

        | `Close ->
          Lwt.wakeup_later notify_read_loop_exited ();
          Io.shutdown_receive socket;
          Lwt.return_unit
      in

      Lwt.async (fun () ->
        Lwt.catch
          read_loop_step
          (fun exn ->
            (*Client_connection.report_exn connection exn;*)
            Printexc.print_backtrace stdout;
            ignore(raise exn);
            Lwt.return_unit))
    in

    let writev = Io.writev socket in
    let write_loop_exited, notify_write_loop_exited = Lwt.wait () in

    let rec write_loop () =
      let rec write_loop_step () =
        flush stdout;
        match Client_connection.next_write_operation connection with
        | `Write io_vectors ->
          writev io_vectors >>= fun result ->
          Client_connection.report_write_result connection result;
          write_loop_step ()

        | `Yield ->
          Client_connection.yield_writer connection write_loop;
          Lwt.return_unit

        | `Close _ ->
          Lwt.wakeup_later notify_write_loop_exited ();
          Io.shutdown_send socket;
          Lwt.return_unit
      in

      Lwt.async (fun () ->
        Lwt.catch
          write_loop_step
          (fun exn ->
            (*Client_connection.report_exn connection exn;*)
            ignore(raise exn);
            Lwt.return_unit))
    in

    read_loop ();
    write_loop ();

    Lwt.join [read_loop_exited; write_loop_exited] >>= fun () ->
    Io.close socket

  let connect ~nonce ~host ~port ~resource ~error_handler ~websocket_handler socket =
    let headers = Httpaf.Headers.of_list
      ["host", String.concat ":" [host; string_of_int port]]
    in
    let connection =
      Client_connection.connect
        ~nonce
        ~headers
        ~sha1
        ~error_handler
        ~websocket_handler
        resource
    in
    start_read_write_loops socket connection

  let create ~websocket_handler socket =
    let connection = Client_connection.create ~websocket_handler in
    start_read_write_loops socket connection
end
