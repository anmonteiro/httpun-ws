let sha1 s =
  s
  |> Digestif.SHA1.digest_string
  |> Digestif.SHA1.to_raw_string
  |> Base64.encode_exn ~pad:true

include Websocketaf_lwt_intf

module Server (Server_runtime: Gluten_lwt.Server) = struct
  (* TODO: should this error handler be a websocket error handler or an HTTP
   * error handler?*)
  let create_connection_handler
    ?(config = Httpaf.Config.default)
    ~websocket_handler
    ~error_handler = fun client_addr socket ->
    let connection =
      Websocketaf.Server_connection.create
        ~sha1
        ~error_handler:(error_handler client_addr)
        (websocket_handler client_addr)
    in
    Server_runtime.create_connection_handler
      ~read_buffer_size:config.read_buffer_size
      ~protocol:(module Websocketaf.Server_connection)
      connection
      client_addr
      socket

  let create_upgraded_connection_handler
    ?(config=Httpaf.Config.default)
    ~websocket_handler
    ~error_handler = fun client_addr socket ->
    let connection =
      Websocketaf.Server_connection.create_upgraded
        ~error_handler:(error_handler client_addr)
        ~websocket_handler:(websocket_handler client_addr)
    in
    Server_runtime.create_connection_handler
      ~read_buffer_size:config.read_buffer_size
      ~protocol:(module Websocketaf.Server_connection)
      connection
      client_addr
      socket
end

module Client (Client_runtime: Gluten_lwt.Client) = struct
  let connect ~nonce ~host ~port ~resource ~error_handler ~websocket_handler socket =
    let headers = Httpaf.Headers.of_list
      ["host", String.concat ":" [host; string_of_int port]]
    in
    let connection =
      Websocketaf.Client_connection.connect
        ~nonce
        ~headers
        ~sha1
        ~error_handler
        ~websocket_handler
        resource
    in
    Lwt.map ignore
      (Client_runtime.create
        ~read_buffer_size:0x1000
        ~protocol:(module Websocketaf.Client_connection)
        connection
        socket)

  let create ~websocket_handler socket =
    let connection = Websocketaf.Client_connection.create ~websocket_handler in
    Lwt.map ignore
      (Client_runtime.create
        ~read_buffer_size:0x1000
        ~protocol:(module Websocketaf.Client_connection)
        connection
        socket)
end
