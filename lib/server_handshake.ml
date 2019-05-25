module IOVec = Httpaf.IOVec

type t =
  { conn: Httpaf.Server_connection.t
  ; mutable pending_bytes: [ `Ok of int | `Error ]
  ; wakeup_reader : (unit -> unit) list ref
  }

let create ~request_handler =
  { conn = Httpaf.Server_connection.create request_handler
  ; pending_bytes = `Ok 0
  ; wakeup_reader = ref []
  }

let next_read_operation t =
  Httpaf.Server_connection.next_read_operation t.conn

let next_write_operation t =
  match Httpaf.Server_connection.next_write_operation t.conn with
  | `Write iovecs as op ->
    begin match t.pending_bytes with
    | `Ok pending_bytes ->
      let lenv = Httpaf.IOVec.lengthv iovecs in
      t.pending_bytes <- `Ok (pending_bytes + lenv);
    | `Error -> ()
    end;
    op
  | op -> op

let read t =
  Httpaf.Server_connection.read t.conn

let read_eof t =
  Httpaf.Server_connection.read_eof t.conn

let report_write_result t result =
  Httpaf.Server_connection.report_write_result t.conn result;
  begin match result with
  | `Ok bytes_written ->
    begin match t.pending_bytes with
    | `Ok pending_bytes ->
      let pending_bytes' = pending_bytes - bytes_written in
      t.pending_bytes <- `Ok pending_bytes';
      `Ok pending_bytes'
    | `Error -> `Error
    end;
  | `Closed -> `Closed
  end

let reset_handshake t =
  t.pending_bytes <- `Ok 0

let report_handshake_failure t =
  t.pending_bytes <- `Error

let on_wakeup_reader t k =
  if Httpaf.Server_connection.is_closed t.conn
  then failwith "on_wakeup_reader on closed conn"
  else t.wakeup_reader := k::!(t.wakeup_reader)

let wakeup_reader t =
  let fs = !(t.wakeup_reader) in
  t.wakeup_reader := [];
  List.iter (fun f -> f ()) fs

let yield_reader t k =
  on_wakeup_reader t k

let yield_writer t =
  Httpaf.Server_connection.yield_writer t.conn

let close t =
  Httpaf.Server_connection.shutdown t.conn
