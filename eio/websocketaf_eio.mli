module type Server = Websocketaf_eio_intf.Server

module type Client = Websocketaf_eio_intf.Client

module Server : Server
  with type socket = Eio.Net.stream_socket

module Client : Client with type socket := Eio.Net.stream_socket
