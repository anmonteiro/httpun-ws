module IOVec = Httpaf.IOVec

type error = [ `Exn of exn ]

type mode =
  [ `Client of unit -> int32
  | `Server
  ]

type t =
  { faraday : Faraday.t
  ; mode : mode
  ; mutable wakeup : Optional_thunk.t
  ; error_handler: error_handler
  ; mutable error_code: [`Ok | error ]
  }
and error_handler = t -> error -> unit

let default_ready_to_write = Sys.opaque_identity (fun () -> ())

let create ~error_handler mode =
  { faraday = Faraday.create 0x1000
  ; mode
  ; wakeup = Optional_thunk.none
  ; error_handler
  ; error_code = `Ok
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
  Serialize.schedule_serialize
    t.faraday
    (* TODO: is_fin *)
    ?mask
    ~is_fin:true
    ~opcode:(kind :> Websocket.Opcode.t)
    ~src_off:0
    ~payload ~off ~len;
  wakeup t

let send_bytes t ~kind payload ~off ~len =
  let mask = mask t in
  Serialize.serialize_bytes
    t.faraday
    ?mask
    ~is_fin:true
    ~opcode:(kind :> Websocket.Opcode.t)
    ~payload
    ~src_off:0
    ~off
    ~len;
  wakeup t

let send_ping ?application_data t =
  begin match application_data with
  | None -> Serialize.serialize_control t.faraday ~opcode:`Ping
  | Some { IOVec.buffer; off; len } ->
    let mask = mask t in
    Serialize.schedule_serialize
      t.faraday
      ?mask
      ~is_fin:true
      ~opcode:`Ping
      ~src_off:0
      ~payload:buffer
      ~off
      ~len;
  end;
  wakeup t

let send_pong ?application_data t =
  begin match application_data with
  | None -> Serialize.serialize_control t.faraday ~opcode:`Pong;
  | Some { IOVec.buffer; off; len } ->
    let mask = mask t in
    Serialize.schedule_serialize
      t.faraday
      ?mask
      ~is_fin:true
      ~opcode:`Pong
      ~src_off:0
      ~payload:buffer
      ~off
      ~len;
  end;
  wakeup t

let flushed t f = Faraday.flush t.faraday f

let close ?code t =
  begin match code with
  | Some code ->
    let mask = mask t in
    let payload = Bytes.create 2 in
    Bytes.set_uint16_be payload 0 (Websocket.Close_code.to_int code);
    Serialize.serialize_bytes t.faraday
      ?mask
      ~is_fin:true
      ~opcode:`Connection_close
      ~src_off:0
      ~payload ~off:0 ~len:2;
  | None -> ()
  end;
  Faraday.close t.faraday;
  wakeup t

let error_code t =
  match t.error_code with
  | #error as error -> Some error
  | `Ok             -> None

let report_error t error =
  match t.error_code with
  | `Ok ->
    t.error_code <- (error :> [`Ok | error]);
    if not (is_closed t)
    then t.error_handler t error
  | `Exn _exn ->
    close ~code:`Abnormal_closure t

let next t =
  match Faraday.operation t.faraday with
  | `Close         -> `Close 0 (* XXX(andreas): should track unwritten bytes *)
  | `Yield         -> `Yield
  | `Writev iovecs -> `Write iovecs

let report_result t result =
  match result with
  | `Closed -> close t
  | `Ok len -> Faraday.shift t.faraday len
