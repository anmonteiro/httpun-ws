open Core
open Async

let sha1 s = s |> Digestif.SHA1.digest_string |> Digestif.SHA1.to_raw_string

module Server = struct
  let create_connection_handler
        ?(config = Httpun.Config.default)
        ?error_handler
        websocket_handler
    =
   fun client_addr socket ->
    let connection =
      Httpun_ws.Server_connection.create
        ~sha1
        ?error_handler:(Option.map ~f:(fun f -> f client_addr) error_handler)
        (websocket_handler client_addr)
    in
    Gluten_async.Server.create_connection_handler
      ~read_buffer_size:config.read_buffer_size
      ~protocol:(module Httpun_ws.Server_connection)
      connection
      client_addr
      socket
end

module Client = struct
  let connect
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
        [ "host", String.concat ~sep:":" [ host; string_of_int port ] ]
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
    Deferred.ignore_m
      (Gluten_async.Client.create
         ~read_buffer_size:0x1000
         ~protocol:(module Httpun_ws.Client_connection)
         connection
         socket)
end
