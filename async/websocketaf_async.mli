open Async

module Server : sig
  val create_connection_handler
    :  ?config : Httpaf.Config.t
    -> websocket_handler : ( 'a
                           -> Websocketaf.Wsd.t
                           -> Websocketaf.Server_connection.input_handlers)
    -> error_handler     : ('a -> Websocketaf.Server_connection.error_handler)
    -> (Socket.Address.Inet.t as 'a)
    -> ([`Active], 'a) Socket.t
    -> unit Deferred.t
end

module Client : sig
  (* Perform HTTP/1.1 handshake and upgrade to WS. *)
  val connect
    :  nonce             : string
    -> host              : string
    -> port              : int
    -> resource          : string
    -> error_handler : (Websocketaf.Client_connection.error -> unit)
    -> websocket_handler : (Websocketaf.Wsd.t -> Websocketaf.Client_connection.input_handlers)
    -> ([`Active], Socket.Address.Inet.t) Socket.t
    -> unit Deferred.t
end
