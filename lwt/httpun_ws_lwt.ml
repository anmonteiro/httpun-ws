let sha1 s = s |> Digestif.SHA1.digest_string |> Digestif.SHA1.to_raw_string

include Httpun_ws_lwt_intf

module Server (Server_runtime : Gluten_lwt.Server) = struct
  type socket = Server_runtime.socket

  (* TODO: should this error handler be a websocket error handler or an HTTP
   * error handler?*)
  let create_connection_handler
        ?(config = Httpun.Config.default)
        ?error_handler
        websocket_handler
    =
   fun client_addr socket ->
    let connection =
      Httpun_ws.Server_connection.create
        ~sha1
        ?error_handler:(Option.map (fun f -> f client_addr) error_handler)
        (websocket_handler client_addr)
    in
    Server_runtime.create_connection_handler
      ~read_buffer_size:config.read_buffer_size
      ~protocol:(module Httpun_ws.Server_connection)
      connection
      client_addr
      socket
end

module Client (Client_runtime : Gluten_lwt.Client) = struct
  type t = Client_runtime.t
  type socket = Client_runtime.socket

  let connect
        ?(config = Httpun.Config.default)
        ~nonce
        ~host
        ~port
        ~resource
        ~error_handler
        ~websocket_handler
        socket
    =
    let headers =
      Httpun.Headers.of_list
        [ "host", String.concat ":" [ host; string_of_int port ] ]
    in
    let connection =
      Httpun_ws.Client_connection.connect
        ~nonce
        ~headers
        ~sha1
        ~error_handler
        ~websocket_handler
        resource
    in
    Client_runtime.create
      ~read_buffer_size:config.read_buffer_size
      ~protocol:(module Httpun_ws.Client_connection)
      connection
      socket

  let is_closed t = Client_runtime.is_closed t
end
