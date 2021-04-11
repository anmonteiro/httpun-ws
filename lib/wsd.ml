module IOVec = Httpaf.IOVec

type mode =
  [ `Client of unit -> int32
  | `Server
  ]

type t =
  { faraday : Faraday.t
  ; mode : mode
  ; mutable wakeup : Optional_thunk.t
  }

let default_ready_to_write = Sys.opaque_identity (fun () -> ())

let create mode =
  { faraday = Faraday.create 0x1000
  ; mode
  ; wakeup = Optional_thunk.none;
  }

let mask t =
  match t.mode with
  | `Client m -> Some (m ())
  | `Server -> None

let is_closed t =
  Faraday.is_closed t.faraday

  let on_wakeup t k =
    if Faraday.is_closed t.faraday
    then failwith "on_wakeup on closed writer"
    else if Optional_thunk.is_some t.wakeup
    then failwith "on_wakeup: only one callback can be registered at a time"
    else t.wakeup <- Optional_thunk.some k

  let wakeup t =
    let f = t.wakeup in
    t.wakeup <- Optional_thunk.none;
    Optional_thunk.call_if_some f

let schedule t ~kind payload ~off ~len =
  let mask = mask t in
  Websocket.Frame.schedule_serialize t.faraday ?mask ~is_fin:true ~opcode:(kind :> Websocket.Opcode.t) ~payload ~off ~len;
  wakeup t

let send_bytes t ~kind payload ~off ~len =
  let mask = mask t in
  Websocket.Frame.serialize_bytes t.faraday ?mask ~is_fin:true ~opcode:(kind :> Websocket.Opcode.t) ~payload ~off ~len;
  wakeup t

let send_ping t =
  Websocket.Frame.serialize_control t.faraday ~opcode:`Ping;
  wakeup t

let send_pong t =
  Websocket.Frame.serialize_control t.faraday ~opcode:`Pong;
  wakeup t

let flushed t f = Faraday.flush t.faraday f

let close ?code t =
  begin match code with
  | Some code ->
    let mask = mask t in
    let payload = Bytes.create 2 in
    Bytes.set_uint16_be payload 0 (Websocket.Close_code.to_int code);
    Websocket.Frame.serialize_bytes t.faraday ?mask ~is_fin:true ~opcode:`Connection_close ~payload ~off:0 ~len:2;
  | None -> ()
  end;
  Faraday.close t.faraday;
  wakeup t

let next t =
  match Faraday.operation t.faraday with
  | `Close         -> `Close 0 (* XXX(andreas): should track unwritten bytes *)
  | `Yield         -> `Yield
  | `Writev iovecs -> `Write iovecs

let report_result t result =
  match result with
  | `Closed -> close t
  | `Ok len -> Faraday.shift t.faraday len
