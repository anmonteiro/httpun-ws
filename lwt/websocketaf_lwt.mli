module type Server = Websocketaf_lwt_intf.Server

module type Client = Websocketaf_lwt_intf.Client

(* The function that results from [create_connection_handler] should be passed
   to [Lwt_io.establish_server_with_client_socket]. For an example, see
   [examples/lwt_echo_server.ml]. *)
module Server (Server_runtime : Gluten_lwt.Server) :
  Server with type socket = Server_runtime.socket
          and type addr := Server_runtime.addr

module Client (Client_runtime : Gluten_lwt.Client) :
  Client with type socket = Client_runtime.socket
