module IOVec = Httpaf.IOVec

type ('fd, 'io) t = ('fd, 'io) Httpaf.Server_connection.t

let create ~request_handler =
  (* TODO: support config too? *)
  Httpaf.Server_connection.create request_handler

let next_read_operation t =
  Httpaf.Server_connection.next_read_operation t

let next_write_operation t =
  Httpaf.Server_connection.next_write_operation t

let read t =
  Httpaf.Server_connection.read t

let read_eof t =
  Httpaf.Server_connection.read_eof t

let report_write_result t result =
  Httpaf.Server_connection.report_write_result t result

let yield_writer t =
  Httpaf.Server_connection.yield_writer t

let is_closed t =
  Httpaf.Server_connection.is_closed t

let close t =
  Httpaf.Server_connection.shutdown t
