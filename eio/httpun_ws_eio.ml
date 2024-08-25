let sha1 s =
  s
  |> Digestif.SHA1.digest_string
  |> Digestif.SHA1.to_raw_string

module Server = struct
  (* TODO: should this error handler be a websocket error handler or an HTTP
   * error handler?*)
  let create_connection_handler
    ?(config = Httpun.Config.default)
    ?error_handler
    ?websocket_error_handler
    ~sw
    websocket_handler =
    fun client_addr socket ->
      let connection =
        Httpun_ws.Server_connection.create
          ~sha1
          ?error_handler:(Option.map (fun f -> f client_addr) error_handler)
          ?websocket_error_handler:(Option.map (fun f -> f client_addr) websocket_error_handler)
          (websocket_handler client_addr)
      in
      Gluten_eio.Server.create_connection_handler
        ~read_buffer_size:config.read_buffer_size
        ~protocol:(module Httpun_ws.Server_connection)
        ~sw
        connection
        client_addr
        socket
end

module Client = struct
  module Client_runtime = Gluten_eio.Client
  type t = Client_runtime.t

  let connect
      ?(config=Httpun.Config.default)
      ~sw
      ~nonce ~host ~port ~resource ~error_handler ~websocket_handler socket =
    let headers = Httpun.Headers.of_list
      ["host", String.concat ":" [host; string_of_int port]]
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
      ~sw
      ~read_buffer_size:config.read_buffer_size
      ~protocol:(module Httpun_ws.Client_connection)
      connection
      socket

  let is_closed t = Client_runtime.is_closed t

  let shutdown t = Client_runtime.shutdown t
end
