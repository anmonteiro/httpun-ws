type mode =
  [ `Client of unit -> int32
  | `Server
  ]

let mask mode =
  match mode with
  | `Client m -> Some (m ())
  | `Server -> None


let serialize_headers ~mode faraday ~is_fin ~opcode ~payload_length =
  let opcode = Websocket.Opcode.to_int opcode in
  let is_fin = if is_fin then 1 lsl 7 else 0 in
  let mask = mask mode in
  let is_mask =
    match mask with
    | None   -> 0
    | Some _ -> 1 lsl 7
  in
  Faraday.write_uint8 faraday (is_fin lor opcode);
  if payload_length <= 125    then
    Faraday.write_uint8 faraday (is_mask lor payload_length)
  else if payload_length <= 0xffff then begin
    Faraday.write_uint8     faraday (is_mask lor 126);
    Faraday.BE.write_uint16 faraday payload_length;
  end else begin
    Faraday.write_uint8     faraday (is_mask lor 127);
    Faraday.BE.write_uint64 faraday (Int64.of_int payload_length);
  end;
  Option.iter (Faraday.BE.write_uint32 faraday) mask;
  mask
;;

let serialize_control ~mode faraday ~opcode =
  let opcode = (opcode :> Websocket.Opcode.t) in
  let _mask: int32 option =
    serialize_headers faraday ~mode ~is_fin:true ~opcode ~payload_length:0
  in
  ()

let schedule_serialize ~mode faraday ~is_fin ~opcode ~payload ~src_off ~off ~len =
  begin match serialize_headers faraday ~mode ~is_fin ~opcode ~payload_length:len with
  | None -> ()
  | Some mask -> Websocket.Frame.apply_mask mask payload ~src_off ~off ~len
  end;
  Faraday.schedule_bigstring faraday payload ~off ~len;
;;

let serialize_bytes ~mode faraday ~is_fin ~opcode ~payload ~src_off ~off ~len =
  begin match serialize_headers faraday ~mode ~is_fin ~opcode ~payload_length:len with
  | None -> ()
  | Some mask -> Websocket.Frame.apply_mask_bytes mask payload ~src_off ~off ~len
  end;
  Faraday.write_bytes faraday payload ~off ~len;
;;
