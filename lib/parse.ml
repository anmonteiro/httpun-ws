type t =
  { payload_length : int
  ; is_fin : bool
  ; mask : int32 option
  ; opcode : Websocket.Opcode.t
  }

let is_fin headers =
  let bits = Bigstringaf.unsafe_get headers 0 |> Char.code in
  bits land (1 lsl 7) = 1 lsl 7

(* let rsv t =
  let bits = Bigstringaf.unsafe_get t.headers 0 |> Char.code in
  (bits lsr 4) land 0b0111
;;
*)

let opcode headers =
  let bits = Bigstringaf.unsafe_get headers 0 |> Char.code in
  bits land 0b1111 |> Websocket.Opcode.unsafe_of_code

let payload_length_of_headers headers =
  let bits = Bigstringaf.unsafe_get headers 1 |> Char.code in
  let length = bits land 0b01111111 in
  if length <= 125
  then
    (* From RFC6455§5.3:
     *   The length of the "Payload data", in bytes: if 0-125, that is the
     *   payload length. *)
    length
  else if length = 126
  then
    (* From RFC6455§5.3:
      * If 126, the following 2 bytes interpreted as a 16-bit unsigned integer
      * are the payload length. *)
    Bigstringaf.unsafe_get_int16_be headers 2
  else (
    assert (length = 127);
    (* This is technically unsafe, but if somebody's asking us to read 2^63
     * bytes, then we're already screwed. *)
    Bigstringaf.unsafe_get_int64_be headers 2 |> Int64.to_int)

(* let payload_length t = payload_length_of_headers t.headers *)

let mask =
  let has_mask headers =
    let bits = Bigstringaf.unsafe_get headers 1 |> Char.code in
    bits land 0b1000_0000 = 0b1000_0000
  in
  let mask_exn headers =
    let bits = Bigstringaf.unsafe_get headers 1 |> Char.code in
    if bits = 254
    then Bigstringaf.unsafe_get_int32_be headers 4
    else if bits = 255
    then Bigstringaf.unsafe_get_int32_be headers 10
    else if bits >= 127
    then Bigstringaf.unsafe_get_int32_be headers 2
    else failwith "Frame.mask_exn: no mask present"
  in
  fun headers ->
    if not (has_mask headers) then None else Some (mask_exn headers)

let payload_offset_of_bits bits =
  let initial_offset = 2 in
  let mask_offset = (bits land (1 lsl 7)) lsr (7 - 2) in
  let length_offset =
    match bits land 0b01111111 with 127 -> 8 | 126 -> 2 | _ -> 0
  in
  initial_offset + mask_offset + length_offset

let payload_offset ?(off = 0) bs =
  let bits = Bigstringaf.unsafe_get bs (off + 1) |> Char.code in
  payload_offset_of_bits bits

let parse_headers =
  let open Angstrom in
  Unsafe.peek 2 (fun bs ~off ~len:_ -> payload_offset ~off bs)
  >>= fun headers_len -> Unsafe.take headers_len Bigstringaf.sub

let payload_parser t payload =
  let open Angstrom in
  let unmask t bs ~src_off =
    match t.mask with
    | None -> bs
    | Some mask ->
      Websocket.Frame.apply_mask mask bs ~src_off;
      bs
  in
  let finish payload =
    Payload.close payload;
    commit
  in
  let schedule_size ~src_off payload n =
    (if Payload.is_closed payload
     then advance n
     else
       take_bigstring n >>| fun bs ->
       let faraday = Payload.unsafe_faraday payload in
       Faraday.schedule_bigstring faraday (unmask ~src_off t bs))
    <* commit
  in
  let read_exact =
    let rec read_exact src_off n =
      if n = 0
      then return ()
      else
        at_end_of_input >>= function
        | true -> commit *> fail "missing payload bytes"
        | false ->
          available >>= fun m ->
          let m' = min m n in
          let n' = n - m' in
          schedule_size ~src_off payload m' >>= fun () ->
          read_exact (src_off + m') n'
    in
    fun n -> read_exact 0 n
  in
  read_exact t.payload_length >>= fun () -> finish payload

let frame =
  let open Angstrom in
  parse_headers >>| fun headers ->
  let payload_length = payload_length_of_headers headers
  and is_fin = is_fin headers
  and opcode = opcode headers
  and mask = mask headers in
  { is_fin; opcode; mask; payload_length }

module Reader = struct
  module AU = Angstrom.Unbuffered

  type 'error parse_state =
    | Done
    | Fail of 'error
    | Partial of
        (Bigstringaf.t -> off:int -> len:int -> AU.more -> unit AU.state)

  type 'error t =
    { parser : unit Angstrom.t
    ; mutable parse_state : 'error parse_state
    ; mutable closed : bool
    ; mutable wakeup : Optional_thunk.t
    }

  let wakeup t =
    let f = t.wakeup in
    t.wakeup <- Optional_thunk.none;
    Optional_thunk.call_if_some f

  let create frame_handler =
    let rec parser t =
      let open Angstrom in
      let buf = Bigstringaf.create 0x1000 in
      skip_many
        ( frame <* commit >>= fun frame ->
          let { payload_length; _ } = frame in
          let payload =
            match payload_length with
            | 0 -> Payload.create_empty ()
            | _ ->
              Payload.create
                buf
                ~when_ready_to_read:
                  (Optional_thunk.some (fun () -> wakeup (Lazy.force t)))
          in
          frame_handler frame payload;
          payload_parser frame payload )
    and t =
      lazy
        { parser = parser t
        ; parse_state = Done
        ; closed = false
        ; wakeup = Optional_thunk.none
        }
    in
    Lazy.force t

  let is_closed t = t.closed

  let on_wakeup t k =
    if is_closed t
    then failwith "on_wakeup on closed reader"
    else if Optional_thunk.is_some t.wakeup
    then failwith "on_wakeup: only one callback can be registered at a time"
    else t.wakeup <- Optional_thunk.some k

  let transition t state =
    match state with
    | AU.Done (consumed, ()) | AU.Fail ((0 as consumed), _, _) ->
      t.parse_state <- Done;
      consumed
    | AU.Fail (consumed, marks, msg) ->
      t.parse_state <- Fail (`Parse (marks, msg));
      consumed
    | AU.Partial { committed; continue } ->
      t.parse_state <- Partial continue;
      committed

  and start t state =
    match state with
    | AU.Done _ -> failwith "httpun-ws.Reader.unable to start parser"
    | AU.Fail (0, marks, msg) -> t.parse_state <- Fail (`Parse (marks, msg))
    | AU.Partial { committed = 0; continue } ->
      t.parse_state <- Partial continue
    | _ -> assert false

  let rec _read_with_more t bs ~off ~len more =
    let initial = match t.parse_state with Done -> true | _ -> false in
    let consumed =
      match t.parse_state with
      | Fail _ -> 0
      (* Don't feed empty input when we're at a request boundary *)
      | Done when len = 0 -> 0
      | Done ->
        start t (AU.parse t.parser);
        _read_with_more t bs ~off ~len more
      | Partial continue -> transition t (continue bs more ~off ~len)
    in
    (* Special case where the parser just started and was fed a zero-length
     * bigstring. Avoid putting them parser in an error state in this scenario.
     * If we were already in a `Partial` state, return the error. *)
    if initial && len = 0 then t.parse_state <- Done;
    match t.parse_state with
    | Done when consumed < len ->
      let off = off + consumed
      and len = len - consumed in
      consumed + _read_with_more t bs ~off ~len more
    | _ -> consumed

  let read_with_more t bs ~off ~len more =
    let consumed = _read_with_more t bs ~off ~len more in
    (match more with Complete -> t.closed <- true | Incomplete -> ());
    consumed

  let force_close t = t.closed <- true

  let next t =
    match t.parse_state with
    | Fail failure -> `Error failure
    | _ when t.closed -> `Close
    | Done -> `Read
    | Partial _ -> `Read
end
