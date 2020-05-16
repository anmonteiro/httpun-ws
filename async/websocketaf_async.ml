open Core
open Async

let sha1 s =
  s
  |> Digestif.SHA1.digest_string
  |> Digestif.SHA1.to_raw_string

module Server = struct
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
    Gluten_async.Server.create_connection_handler
      ~read_buffer_size:config.read_buffer_size
      ~protocol:(module Websocketaf.Server_connection)
      connection
      client_addr
      socket
end

module Client = struct
  let connect ~nonce ~host ~port ~resource ~error_handler ~websocket_handler socket =
    let headers = Httpaf.Headers.of_list
      ["host", String.concat ~sep:":" [host; string_of_int port]]
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
    Deferred.ignore_m
      (Gluten_async.Client.create
        ~read_buffer_size:0x1000
        ~protocol:(module Websocketaf.Client_connection)
        connection
        socket)
end
