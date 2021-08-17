module IOVec = Httpaf.IOVec

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
  end

  module Frame : sig
    type t

    val is_fin   : t -> bool
    val rsv      : t -> int

    val opcode   : t -> Opcode.t

    val has_mask : t -> bool
    val mask     : t -> int32 option
    val mask_exn : t -> int32

    val payload : t -> Payload.t
    val payload_length : t -> int
    val length : t -> int

    val parse : buf:Bigstringaf.t -> t Angstrom.t
    val payload_parser : t -> unit Angstrom.t

    val serialize_control : ?mask:int32 -> Faraday.t -> opcode:Opcode.standard_control -> unit

    val schedule_serialize
      :  ?mask:int32
      -> Faraday.t
      -> is_fin:bool
      -> opcode:Opcode.t
      -> payload:Bigstringaf.t
      -> off:int
      -> len:int
      -> unit

    val serialize_bytes
      :  ?mask:int32
      -> Faraday.t
      -> is_fin:bool
      -> opcode:Opcode.t
      -> payload:Bytes.t
      -> off:int
      -> len:int
      -> unit
  end
end

module Wsd : sig

  type mode =
    [ `Client of unit -> int32
    | `Server
    ]

  type t

  val create
    : mode
    -> t

  val schedule
    :  t
    -> kind:[ `Text | `Binary | `Continuation ]
    -> Bigstringaf.t
    -> off:int
    -> len:int
    -> unit

  val send_bytes
    :  t
    -> kind:[ `Text | `Binary | `Continuation ]
    -> Bytes.t
    -> off:int
    -> len:int
    -> unit

  val send_ping : t -> unit
  val send_pong : t -> unit

  val flushed : t -> (unit -> unit) -> unit
  val close   : ?code:Websocket.Close_code.t -> t -> unit

  val is_closed : t -> bool
end

module Handshake : sig
  val create_request
    :  nonce:string
    -> headers:Httpaf.Headers.t
    -> string
    -> Httpaf.Request.t

  val upgrade_headers
  :  sha1:(string -> string)
  -> request_method:Httpaf.Method.t
  -> Httpaf.Headers.t
  -> ((string * string) list, string) result

  val respond_with_upgrade
  : ?headers:Httpaf.Headers.t
  -> sha1:(string -> string)
  -> Httpaf.Reqd.t
  -> (unit -> unit)
  -> (unit, string) result
end

module Client_connection : sig
  type t

  type error =
    [ Httpaf.Client_connection.error
    | `Handshake_failure of Httpaf.Response.t * Httpaf.Body.Reader.t ]

  type input_handlers =
    { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> len:int -> Payload.t -> unit
    ; eof   : unit -> unit }

  val connect
    :  nonce             : string
    -> ?headers          : Httpaf.Headers.t
    -> sha1              : (string -> string)
    -> error_handler     : (error -> unit)
    -> websocket_handler : (Wsd.t -> input_handlers)
    -> string
    -> t

  val create
    :  ?error_handler:(Wsd.t -> [`Exn of exn] -> unit)
    -> (Wsd.t -> input_handlers) -> t

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

  type input_handlers =
    { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> len:int -> Payload.t -> unit
    ; eof   : unit -> unit }

  type error = [ `Exn of exn ]

  type error_handler = Wsd.t -> error -> unit

  (* TODO: should take handshake error handler. *)
  val create
    : sha1 : (string -> string)
    -> ?error_handler : error_handler
    -> (Wsd.t -> input_handlers)
    -> t

  val create_websocket
  : ?error_handler:error_handler
  -> (Wsd.t -> input_handlers)
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
