open Async

module Client : sig
  val connect
    : ([`Active], [< Socket.Address.t]) Socket.t
    -> nonce             : string
    -> host              : string
    -> port              : int
    -> resource          : string
    -> error_handler : (Websocketaf.Client_connection.error -> unit)
    -> websocket_handler : (Websocketaf.Wsd.t -> Websocketaf.Client_connection.input_handlers)
    -> unit Deferred.t
end

module Server : sig
  val create_connection_handler
    :  ?config : Httpaf.Config.t
    -> websocket_handler : ( 'a
                           -> Websocketaf.Wsd.t
                           -> Websocketaf.Server_connection.input_handlers)
    -> error_handler     : ('a -> Httpaf.Server_connection.error_handler)
    -> ([< Socket.Address.t] as 'a)
    -> ([`Active], 'a) Socket.t
    -> unit Deferred.t

  val create_upgraded_connection_handler
    :  ?config : Httpaf.Config.t
    -> websocket_handler :
      (([< Socket.Address.t] as 'a)
      -> Websocketaf.Wsd.t
      -> Websocketaf.Server_connection.input_handlers)
    -> error_handler : Websocketaf.Server_connection.error_handler
    -> ('a -> ([`Active], 'a) Socket.t -> unit Deferred.t)

  val respond_with_upgrade
  : ?headers : Httpaf.Headers.t
  -> (([`Active], [< Socket.Address.t] as 'a) Socket.t, unit Deferred.t) Httpaf.Reqd.t
  -> (([`Active], 'a) Socket.t -> unit Deferred.t)
  -> (unit, string) Deferred.Result.t
end
