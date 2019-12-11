module Wsd : sig
  module IOVec = Httpaf.IOVec

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
    -> kind:[ `Text | `Binary ]
    -> Bigstringaf.t
    -> off:int
    -> len:int
    -> unit

  val send_bytes
    :  t
    -> kind:[ `Text | `Binary ]
    -> Bytes.t
    -> off:int
    -> len:int
    -> unit

  val send_ping : t -> unit
  val send_pong : t -> unit

  val flushed : t -> (unit -> unit) -> unit
  val close   : t -> unit

  val next : t -> [ `Write of Bigstringaf.t IOVec.t list | `Yield | `Close of int ]
  val report_result : t -> [`Ok of int | `Closed ] -> unit

  val is_closed : t -> bool

  val when_ready_to_write : t -> (unit -> unit) -> unit
end

module Handshake : sig
  val create_request
    :  nonce:string
    -> headers:Httpaf.Headers.t
    -> string
    -> Httpaf.Request.t

  val create_response_headers
    :  sha1:(string -> string)
    -> sec_websocket_key:string
    -> headers:Httpaf.Headers.t
    -> Httpaf.Headers.t
end

module Client_connection : sig
  type t

  type error =
    [ Httpaf.Client_connection.error
    | `Handshake_failure of Httpaf.Response.t * [`read] Httpaf.Body.t ]

  type input_handlers = Client_websocket.input_handlers =
    { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> Bigstringaf.t -> off:int -> len:int -> unit
    ; eof   : unit                                                                          -> unit }

  val connect
    :  nonce             : string
    -> ?headers          : Httpaf.Headers.t
    -> sha1              : (string -> string)
    -> error_handler     : (error -> unit)
    -> websocket_handler : (Wsd.t -> input_handlers)
    -> string
    -> t

  val create : websocket_handler : (Wsd.t -> input_handlers) -> t

  val next_read_operation  : t -> [ `Read | `Yield | `Close ]
  val next_write_operation
    :  t
    -> [ `Write of Bigstringaf.t Httpaf.IOVec.t list | `Yield | `Close of int ]

  val read : t -> Bigstringaf.t -> off:int -> len:int -> int
  val read_eof : t -> Bigstringaf.t -> off:int -> len:int -> int

  val yield_reader : t -> (unit -> unit) -> unit

  val report_write_result : t -> [`Ok of int | `Closed ] -> unit

  val yield_writer : t -> (unit -> unit) -> unit

  val close : t -> unit
end

module Server_connection : sig
  type ('fd, 'io) t

  type input_handlers =
    { frame : opcode:Websocket.Opcode.t -> is_fin:bool -> Bigstringaf.t -> off:int -> len:int -> unit
    ; eof   : unit                                                                          -> unit }

  type error = [ `Exn of exn ]

  type error_handler = Wsd.t -> error -> unit

  val create
    : sha1 : (string -> string)
    -> future : 'io
    -> ?error_handler : error_handler
    -> (Wsd.t -> input_handlers)
    -> (_, 'io) t

  val create_upgraded
  : ?error_handler:(Wsd.t -> [ `Exn of exn ] -> unit)
  -> websocket_handler:(Wsd.t -> input_handlers)
  -> _ t

  val respond_with_upgrade
  : ?headers:Httpaf.Headers.t
  -> sha1:(string -> string)
  -> ('fd, 'io) Httpaf.Reqd.t
  -> ('fd -> 'io)
  -> (unit, string) result

  val next_read_operation  : _ t -> [ `Read | `Yield | `Close | `Upgrade ]
  val next_write_operation : ('fd, 'io) t -> [
    | `Write of Bigstringaf.t Httpaf.IOVec.t list
    | `Upgrade of Bigstringaf.t Httpaf.IOVec.t list * ('fd -> 'io)
    | `Yield
    | `Close of int ]

  val read : _ t -> Bigstringaf.t -> off:int -> len:int -> int
  val read_eof : _ t -> Bigstringaf.t -> off:int -> len:int -> int
  val report_write_result : _ t -> [`Ok of int | `Closed ] -> unit

  val report_exn : _ t -> exn -> unit

  val yield_reader : _ t -> (unit -> unit) -> unit
  val yield_writer : _ t -> (unit -> unit) -> unit

  val close : _ t -> unit
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

    val mask_inplace   : t -> unit
    val unmask_inplace   : t -> unit

    val length : t -> int

    val payload_length : t -> int
    val with_payload   : t -> f:(Bigstringaf.t -> off:int -> len:int -> 'a) -> 'a

    val copy_payload       : t -> Bigstringaf.t
    val copy_payload_bytes : t -> Bytes.t

    val parse : t Angstrom.t

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

    val schedule_serialize_bytes
      :  ?mask:int32
      -> Faraday.t
      -> is_fin:bool
      -> opcode:Opcode.t
      -> payload:Bytes.t
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
