module IOVec = Httpun.IOVec

module Payload : sig
  type t

  val is_closed : t -> bool

  val schedule_read :
    t ->
    on_eof:(unit -> unit) ->
    on_read:(Bigstringaf.t -> off:int -> len:int -> unit) ->
    unit

  val close : t -> unit
end

module Websocket : sig
  module Opcode : sig
    type standard_non_control =
      [ `Continuation
      | `Text
      | `Binary ]

    type standard_control =
      [ `Connection_close
      | `Ping
      | `Pong ]

    type standard =
      [ standard_non_control
      | standard_control ]

    type t =
      [ standard
      | `Other of int ]

    val code   : t -> int

    val of_code     : int -> t option
    val of_code_exn : int -> t

    val to_int : t -> int

    val of_int     : int -> t option
    val of_int_exn : int -> t

    val pp_hum : Format.formatter -> t -> unit
  end

  module Close_code : sig
    type standard =
      [ `Normal_closure
      | `Going_away
      | `Protocol_error
      | `Unsupported_data
      | `No_status_rcvd
      | `Abnormal_closure
      | `Invalid_frame_payload_data
      | `Policy_violation
      | `Message_too_big
      | `Mandatory_ext
      | `Internal_server_error
      | `TLS_handshake ]

    type t =
      [ standard | `Other of int ]

    val code : t -> int

    val of_code     : int -> t option
    val of_code_exn : int -> t

    val to_int : t -> int

    val of_int     : int -> t option
    val of_int_exn : int -> t

    val of_bigstring : Bigstringaf.t -> off:int -> t option
    val of_bigstring_exn : Bigstringaf.t -> off:int -> t
  end
end

module Wsd : sig

  type mode =
    [ `Client of unit -> int32
    | `Server
    ]

  type t

  val schedule
    :  t
    -> ?is_fin:bool
    -> kind:[ `Text | `Binary | `Continuation ]
    -> Bigstringaf.t
    -> off:int
    -> len:int
    -> unit
  (** [is_fin] defaults to [true]. Set to `false` if sending multiple frames,
      except on the last one.
      {b NOTE}: this function mutates the bigarray on clients due to the
      WebSocket protocol masking requirements. *)

  val send_bytes
    :  t
    -> ?is_fin:bool
    -> kind:[ `Text | `Binary | `Continuation ]
    -> Bytes.t
    -> off:int
    -> len:int
    -> unit
  (** [is_fin] defaults to [true]. Set to `false` if sending multiple frames,
      except on the last one.
      {b NOTE}: this function mutates the `bytes` argument on clients due to
      the WebSocket protocol masking requirements. *)

  val send_ping : ?application_data:Bigstringaf.t IOVec.t -> t -> unit
  val send_pong : ?application_data:Bigstringaf.t IOVec.t -> t -> unit

  val flushed : t -> (unit -> unit) -> unit
  val close   : ?code:Websocket.Close_code.t -> t -> unit

  val is_closed : t -> bool
  val error_code : t -> [> `Exn of exn] option
end

module Handshake : sig
  val create_request
    :  nonce:string
    -> headers:Httpun.Headers.t
    -> string
    -> Httpun.Request.t

  val upgrade_headers
  :  sha1:(string -> string)
  -> request_method:Httpun.Method.t
  -> Httpun.Headers.t
  -> ((string * string) list, string) result

  val respond_with_upgrade
  : ?headers:Httpun.Headers.t
  -> sha1:(string -> string)
  -> Httpun.Reqd.t
  -> (unit -> unit)
  -> (unit, string) result
end

module Websocket_connection : sig
  type input_handlers =
    { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> len:int -> Payload.t -> unit
    ; eof   : unit -> unit }
end

module Client_connection : sig
  type t

  type error =
    [ Httpun.Client_connection.error
    | `Handshake_failure of Httpun.Response.t * Httpun.Body.Reader.t ]

  val connect
    :  nonce             : string
    -> ?headers          : Httpun.Headers.t
    -> sha1              : (string -> string)
    -> error_handler     : (error -> unit)
    -> websocket_handler : (Wsd.t -> Websocket_connection.input_handlers)
    -> string
    -> t

  val create
    :  ?error_handler:(Wsd.t -> [`Exn of exn] -> unit)
    -> (Wsd.t -> Websocket_connection.input_handlers) -> t

  val next_read_operation  : t -> [ `Read | `Yield | `Close ]
  val next_write_operation
    :  t
    -> [ `Write of Bigstringaf.t IOVec.t list | `Yield | `Close of int ]

  val read : t -> Bigstringaf.t -> off:int -> len:int -> int
  val read_eof : t -> Bigstringaf.t -> off:int -> len:int -> int

  val yield_reader : t -> (unit -> unit) -> unit

  val report_write_result : t -> [`Ok of int | `Closed ] -> unit

  val yield_writer : t -> (unit -> unit) -> unit

  val report_exn : t -> exn -> unit

  val is_closed : t -> bool

  val shutdown : t -> unit
end

module Server_connection : sig
  type t

  type error = [ `Exn of exn ]

  type error_handler = Wsd.t -> error -> unit

  (* TODO: should take handshake error handler. *)
  val create
    : ?config : Httpun.Config.t
    -> ?error_handler : Httpun.Server_connection.error_handler
    -> ?websocket_error_handler : error_handler
    -> sha1 : (string -> string)
    -> (Wsd.t -> Websocket_connection.input_handlers)
    -> t

  val create_websocket
  : ?error_handler:error_handler
  -> (Wsd.t -> Websocket_connection.input_handlers)
  -> t

  val next_read_operation  : t -> [ `Read | `Yield | `Close ]
  val next_write_operation : t -> [
    | `Write of Bigstringaf.t IOVec.t list
    | `Yield
    | `Close of int ]

  val read : t -> Bigstringaf.t -> off:int -> len:int -> int
  val read_eof : t -> Bigstringaf.t -> off:int -> len:int -> int
  val report_write_result : t -> [`Ok of int | `Closed ] -> unit

  val report_exn : t -> exn -> unit

  val yield_reader : t -> (unit -> unit) -> unit
  val yield_writer : t -> (unit -> unit) -> unit

  val is_closed : t -> bool

  val shutdown : t -> unit
end
