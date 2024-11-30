open Async

module Server : sig
  val create_connection_handler :
     ?config:Httpun.Config.t
    -> ?error_handler:('a -> Httpun.Server_connection.error_handler)
    -> ('a -> Httpun_ws.Wsd.t -> Httpun_ws.Websocket_connection.input_handlers)
    -> 'a
    -> ([ `Active ], ([< Socket.Address.t ] as 'a)) Socket.t
    -> unit Deferred.t
end

module Client : sig
  (* Perform HTTP/1.1 handshake and upgrade to WS. *)
  val connect :
     nonce:string
    -> host:string
    -> port:int
    -> resource:string
    -> error_handler:(Httpun_ws.Client_connection.error -> unit)
    -> websocket_handler:
         (Httpun_ws.Wsd.t -> Httpun_ws.Websocket_connection.input_handlers)
    -> ([ `Active ], [< Socket.Address.t ]) Socket.t
    -> unit Deferred.t
end
