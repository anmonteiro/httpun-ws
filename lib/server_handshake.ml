module IOVec = Httpaf.IOVec

type 'handle t = 'handle Httpaf.Server_connection.t

let create ~request_handler ~fd =
  Httpaf.Server_connection.create ~fd request_handler

let next_read_operation t =
  Httpaf.Server_connection.next_read_operation t

let next_write_operation t =
  Httpaf.Server_connection.next_write_operation t

let read t =
  Httpaf.Server_connection.read t

let read_eof t =
  Httpaf.Server_connection.read_eof t

let report_write_result t =
  Httpaf.Server_connection.report_write_result t

let yield_reader t =
  Httpaf.Server_connection.yield_writer t

let yield_writer t =
  Httpaf.Server_connection.yield_writer t

let close t =
  Httpaf.Server_connection.shutdown t
