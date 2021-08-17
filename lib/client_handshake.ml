module IOVec = Httpaf.IOVec

type t =
  { connection : Httpaf.Client_connection.t
  ; body       : Httpaf.Body.Writer.t }

(* TODO(anmonteiro): yet another argument, `~config` *)
let create
    ~nonce
    ~headers
    ~error_handler
    ~response_handler
    target
  =
  let connection = Httpaf.Client_connection.create ?config:None in
  let body =
    Httpaf.Client_connection.request
      connection
      (Handshake.create_request ~nonce ~headers target)
      ~error_handler
      ~response_handler
  in
  { connection
  ; body
  }
;;

let next_read_operation t =
  Httpaf.Client_connection.next_read_operation t.connection

let next_write_operation t =
  Httpaf.Client_connection.next_write_operation t.connection

let read t =
  Httpaf.Client_connection.read t.connection

let yield_reader t =
  Httpaf.Client_connection.yield_reader t.connection

let report_write_result t =
  Httpaf.Client_connection.report_write_result t.connection

let yield_writer t =
  Httpaf.Client_connection.yield_writer t.connection

let report_exn t exn =
  Httpaf.Client_connection.report_exn t.connection exn

let is_closed t =
  Httpaf.Client_connection.is_closed t.connection

let close t =
  Httpaf.Body.Writer.close t.body;
  Httpaf.Client_connection.shutdown t.connection
