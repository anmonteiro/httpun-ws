module type IO = Websocketaf_lwt_intf.IO

module type Server = Websocketaf_lwt_intf.Server

module type Client = Websocketaf_lwt_intf.Client

(* The function that results from [create_connection_handler] should be passed
   to [Lwt_io.establish_server_with_client_socket]. For an example, see
   [examples/lwt_echo_server.ml]. *)
module Server (Io: IO) : Server with type socket := Io.socket and type addr := Io.addr

(* For an example, see [examples/lwt_get.ml]. *)
module Client (Io: IO) : Client with type socket := Io.socket

