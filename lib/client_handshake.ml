module IOVec = Httpun.IOVec

type t =
  { connection : Httpun.Client_connection.t
  ; body : Httpun.Body.Writer.t
  }

(* TODO(anmonteiro): yet another argument, `~config` *)
let create ~nonce ~headers ~error_handler ~response_handler target =
  let connection = Httpun.Client_connection.create () in
  let body =
    Httpun.Client_connection.request
      connection
      (Handshake.create_request ~nonce ~headers target)
      ~error_handler
      ~response_handler
      ~flush_headers_immediately:true
  in
  { connection; body }

let next_read_operation t =
  Httpun.Client_connection.next_read_operation t.connection

let next_write_operation t =
  Httpun.Client_connection.next_write_operation t.connection

let read t = Httpun.Client_connection.read t.connection
let read_eof t = Httpun.Client_connection.read_eof t.connection
let yield_reader t = Httpun.Client_connection.yield_reader t.connection

let report_write_result t =
  Httpun.Client_connection.report_write_result t.connection

let yield_writer t = Httpun.Client_connection.yield_writer t.connection
let report_exn t exn = Httpun.Client_connection.report_exn t.connection exn
let is_closed t = Httpun.Client_connection.is_closed t.connection

let close t =
  Httpun.Body.Writer.close t.body;
  Httpun.Client_connection.shutdown t.connection
