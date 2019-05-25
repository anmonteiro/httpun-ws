module Client : sig
  val connect
    :  Lwt_unix.file_descr
    -> nonce             : string
    -> host              : string
    -> port              : int
    -> resource          : string
    -> error_handler : (Websocketaf.Client_connection.error -> unit)
    -> websocket_handler : (Websocketaf.Wsd.t -> Websocketaf.Client_connection.input_handlers)
    -> unit Lwt.t
end

module Server : sig
  val create_connection_handler
    :  ?config : Httpaf.Config.t
    -> websocket_handler : (Unix.sockaddr -> Websocketaf.Wsd.t -> Websocketaf.Server_connection.input_handlers)
    -> error_handler : (Unix.sockaddr -> Httpaf.Server_connection.error_handler)
      -> (Unix.sockaddr -> Lwt_unix.file_descr -> unit Lwt.t)

  val upgrade_connection
    :  ?config : Httpaf.Config.t
    -> ?headers: Httpaf.Headers.t
    -> reqd : Httpaf.Reqd.t
    -> error_handler : Websocketaf.Server_connection.error_handler
    -> websocket_handler: (Websocketaf.Wsd.t -> Websocketaf.Server_connection.input_handlers)
    -> Lwt_unix.file_descr
    -> (unit, string) result Lwt.t
end
