let serialize_headers ?mask faraday ~is_fin ~opcode ~payload_length =
  let opcode = Websocket.Opcode.to_int opcode in
  let is_fin = if is_fin then 1 lsl 7 else 0 in
  let is_mask =
    match mask with
    | None   -> 0
    | Some _ -> 1 lsl 7
  in
  Faraday.write_uint8 faraday (is_fin lor opcode);
  if      payload_length <= 125    then
    Faraday.write_uint8 faraday (is_mask lor payload_length)
  else if payload_length <= 0xffff then begin
    Faraday.write_uint8     faraday (is_mask lor 126);
    Faraday.BE.write_uint16 faraday payload_length;
  end else begin
    Faraday.write_uint8     faraday (is_mask lor 127);
    Faraday.BE.write_uint64 faraday (Int64.of_int payload_length);
  end;
  begin match mask with
  | None      -> ()
  | Some mask -> Faraday.BE.write_uint32 faraday mask
  end
;;

let serialize_control ?mask faraday ~opcode =
  let opcode = (opcode :> Websocket.Opcode.t) in
  serialize_headers faraday ?mask ~is_fin:true ~opcode ~payload_length:0

let schedule_serialize ?mask faraday ~is_fin ~opcode ~payload ~src_off ~off ~len =
  serialize_headers faraday ?mask ~is_fin ~opcode ~payload_length:len;
  begin match mask with
  | None -> ()
  | Some mask -> Websocket.Frame.apply_mask mask payload ~src_off ~off ~len
  end;
  Faraday.schedule_bigstring faraday payload ~off ~len;
;;

let serialize_bytes ?mask faraday ~is_fin ~opcode ~payload ~src_off ~off ~len =
  serialize_headers faraday ?mask ~is_fin ~opcode ~payload_length:len;
  begin match mask with
  | None -> ()
  | Some mask -> Websocket.Frame.apply_mask_bytes mask payload ~src_off ~off ~len
  end;
  Faraday.write_bytes faraday payload ~off ~len;
;;
