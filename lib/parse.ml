type t =
{ headers: Bigstringaf.t
; payload: Payload.t
}

let is_fin t =
  let bits = Bigstringaf.unsafe_get t.headers 0 |> Char.code in
  bits land (1 lsl 7) = 1 lsl 7
;;

let rsv t =
  let bits = Bigstringaf.unsafe_get t.headers 0 |> Char.code in
  (bits lsr 4) land 0b0111
;;

let opcode t =
  let bits = Bigstringaf.unsafe_get t.headers 0 |> Char.code in
  bits land 0b1111 |> Websocket.Opcode.unsafe_of_code
;;

let payload_length_of_headers headers =
  let bits = Bigstringaf.unsafe_get headers 1 |> Char.code in
  let length = bits land 0b01111111 in
  if length = 126 then Bigstringaf.unsafe_get_int16_be headers 2                 else
  (* This is technically unsafe, but if somebody's asking us to read 2^63
   * bytes, then we're already screwed. *)
  if length = 127 then Bigstringaf.unsafe_get_int64_be headers 2 |> Int64.to_int else
  length
;;

let payload_length t = payload_length_of_headers t.headers

let has_mask t =
  let bits = Bigstringaf.unsafe_get t.headers 1 |> Char.code in
  bits land (1 lsl 7) = 1 lsl 7
;;

let mask t =
  if not (has_mask t)
  then None
  else
    Some (
      let bits = Bigstringaf.unsafe_get t.headers 1 |> Char.code in
      if bits  = 254 then Bigstringaf.unsafe_get_int32_be t.headers 4  else
      if bits  = 255 then Bigstringaf.unsafe_get_int32_be t.headers 10 else
      Bigstringaf.unsafe_get_int32_be t.headers 2)
;;

let mask_exn t =
  let bits = Bigstringaf.unsafe_get t.headers 1 |> Char.code in
  if bits  = 254 then Bigstringaf.unsafe_get_int32_be t.headers 4  else
  if bits  = 255 then Bigstringaf.unsafe_get_int32_be t.headers 10 else
  if bits >= 127 then Bigstringaf.unsafe_get_int32_be t.headers 2  else
  failwith "Frame.mask_exn: no mask present"
;;

let payload t = t.payload

let length t =
  let payload_length = payload_length t in
  Bigstringaf.length t.headers + payload_length
;;

let payload_offset_of_bits bits =
  let initial_offset = 2 in
  let mask_offset    = (bits land (1 lsl 7)) lsr (7 - 2) in
  let length_offset  =
    let length = bits land 0b01111111 in
    if length < 126
    then 0
    else 2 lsl ((length land 0b1) lsl 2)
  in
  initial_offset + mask_offset + length_offset
;;

let payload_offset ?(off=0) bs =
  let bits = Bigstringaf.unsafe_get bs (off + 1) |> Char.code in
  payload_offset_of_bits bits
;;

let parse_headers =
  let open Angstrom in
  Unsafe.peek 2 (fun bs ~off ~len:_ -> payload_offset ~off bs)
  >>= fun headers_len -> Unsafe.take headers_len Bigstringaf.sub
;;

let payload_parser t =
  let open Angstrom in
  let unmask t bs ~src_off =
    match mask t with
    | None -> bs
    | Some mask ->
      Websocket.Frame.apply_mask mask bs ~src_off;
      bs
  in
  let finish payload =
    let open Angstrom in
    Payload.close payload;
    commit
  in
  let schedule_size ~src_off payload n =
    Format.eprintf "sched %d; src_off: %d@." n src_off;
    let open Angstrom in
    begin if Payload.is_closed payload
    then advance n
    else take_bigstring n >>| fun bs ->
      let `Hex x = Hex.of_string (Bigstringaf.to_string bs) in
      Format.eprintf "x: %s" x;
      let faraday = Payload.unsafe_faraday payload in
      Faraday.schedule_bigstring faraday (unmask ~src_off t bs)
    end *> commit
  in
  let read_exact =
    let rec read_exact src_off n =
      if n = 0
      then return ()
      else
        at_end_of_input
        >>= function
          | true -> commit *> fail "missing payload bytes"
          | false ->
            available >>= fun m ->
            let m' = (min m n) in
            let n' = n - m' in
            Format.eprintf "do it %d %d@." m' n';
            schedule_size ~src_off t.payload m' >>= fun () -> read_exact (src_off + m') n'
    in
    fun n -> read_exact 0 n
  in
  read_exact (payload_length t)
  >>= fun () -> finish t.payload
;;

let parse ~buf =
  let open Angstrom in
  parse_headers
  >>| fun headers ->
    let len = payload_length_of_headers headers in
    let payload = match len with
    | 0 -> Payload.empty
    | _ -> Payload.create buf
    in
    { headers; payload }
;;

module Reader = struct
  module AU = Angstrom.Unbuffered

  type 'error parse_state =
    | Done
    | Fail    of 'error
    | Partial of (Bigstringaf.t -> off:int -> len:int -> AU.more -> unit AU.state)

  type 'error t =
    { parser : unit Angstrom.t
    ; mutable parse_state : 'error parse_state
    ; mutable closed      : bool }

  let create frame_handler =
    let parser =
      let open Angstrom in
      let buf = Bigstringaf.create 0x1000 in
      skip_many
        (parse ~buf <* commit >>= fun frame ->
          let payload = payload frame in
          let is_fin = is_fin frame in
          let opcode = opcode frame in
          let len = payload_length frame in
          frame_handler ~opcode ~is_fin ~len payload;
          payload_parser frame)
    in
    { parser
    ; parse_state = Done
    ; closed      = false
    }
  ;;

  let transition t state =
    match state with
    | AU.Done(consumed, ())
    | AU.Fail(0 as consumed, _, _) ->
      t.parse_state <- Done;
      consumed
    | AU.Fail(consumed, marks, msg) ->
      t.parse_state <- Fail (`Parse(marks, msg));
      consumed
    | AU.Partial { committed; continue } ->
      t.parse_state <- Partial continue;
      committed
  and start t state =
      match state with
      | AU.Done _         -> failwith "websocketaf.Reader.unable to start parser"
      | AU.Fail(0, marks, msg) ->
        t.parse_state <- Fail (`Parse(marks, msg))
      | AU.Partial { committed = 0; continue } ->
        t.parse_state <- Partial continue
      | _ -> assert false

  let rec read_with_more t bs ~off ~len more =
    let consumed =
      match t.parse_state with
      | Fail _ -> 0
      | Done   ->
        start t (AU.parse t.parser);
        read_with_more  t bs ~off ~len more;
      | Partial continue ->
        transition t (continue bs more ~off ~len)
    in
    begin match more with
    | Complete -> t.closed <- true;
    | Incomplete -> ()
    end;
    consumed

  let next t =
    match t.parse_state with
    | Done ->
      if t.closed
      then `Close
      else `Read
    | Fail failure -> `Error failure
    | Partial _ -> `Read
end
